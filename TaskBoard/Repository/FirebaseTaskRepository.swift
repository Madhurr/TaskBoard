import FirebaseDatabase
import Foundation

/// Realtime Database backed `TaskRepository`.
///
/// The design leans on one property of the Firebase SDK: with persistence enabled,
/// the local cache is a real database. Reads are served from it immediately at
/// launch, writes are applied to it synchronously and queued durably, and the queue
/// survives being killed in the app switcher. That is what makes this app usable
/// offline without a second store to keep in step.
///
/// What Firebase does *not* provide is any view of that queue, so `PendingWriteTracker`
/// mirrors it for the UI. Everything that actually delivers a write is still Firebase's.
actor FirebaseTaskRepository: TaskRepository {

    /// Firebase's references are documented as thread-safe and its callbacks arrive
    /// on its own queue, so these are reachable from the `nonisolated` methods that
    /// register observers and enqueue writes. That indirection is not decoration:
    /// a closure formed inside actor-isolated code captures that isolation, which
    /// Swift 6 rejects when handing it to a callback-based API like this one.
    private nonisolated(unsafe) let tasksRef: DatabaseReference
    private nonisolated(unsafe) let connectedRef: DatabaseReference

    private let tracker: PendingWriteTracker
    private let observers = ObserverRegistry()

    private var tasks: [BoardTask] = []
    private var pendingIDs: Set<BoardTask.ID> = []
    private var isConnected = false
    private var lastError: SyncIssue?

    private var hasStarted = false
    /// Set once a value event has arrived while connected, which is the point at
    /// which Firebase has replayed anything it had queued from a previous launch.
    private var hasRoundTrippedWhileConnected = false

    private var continuations: [UUID: AsyncStream<RepositorySnapshot>.Continuation] = [:]

    init(database: Database, tracker: PendingWriteTracker = PendingWriteTracker()) {
        self.tasksRef = database.reference(withPath: "tasks")
        self.connectedRef = database.reference(withPath: ".info/connected")
        self.tracker = tracker
    }

    // MARK: - TaskRepository

    nonisolated func snapshots() -> AsyncStream<RepositorySnapshot> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.register(continuation, id: id) }
            continuation.onTermination = { _ in
                Task { await self.unregister(id) }
            }
        }
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true

        pendingIDs = await tracker.current
        attachObservers()
        emit()
    }

    /// Writes locally and hands the change to Firebase's queue.
    ///
    /// Deliberately does not await the server. `updateChildValues` applies to the
    /// local cache immediately and its completion handler fires only on
    /// acknowledgement — which, offline, is never. Awaiting it would hang every
    /// edit made without a connection, so the acknowledgement is handled out of
    /// band and shows up as a change in `pendingIDs`.
    func save(_ incoming: [BoardTask]) async throws {
        guard !incoming.isEmpty else { return }

        let ids = incoming.map(\.id)
        pendingIDs.formUnion(ids)
        await tracker.markPending(ids)
        lastError = nil
        emit()

        enqueue(incoming)
    }

    func clearError() async {
        lastError = nil
        emit()
    }

    // MARK: - Firebase plumbing (nonisolated)

    private nonisolated func attachObservers() {
        // Keeps the node warm in the local cache so a cold launch has data to show
        // before — or entirely without — reaching the network.
        tasksRef.keepSynced(true)

        let tasksHandle = tasksRef.observe(.value) { @Sendable [weak self] snapshot in
            // Decoded here, on Firebase's callback queue, so only Sendable values
            // cross into the actor.
            let decoded = BoardTask.decodeAll(from: snapshot.value)
            Task { await self?.applyRemote(decoded) }
        } withCancel: { @Sendable [weak self] error in
            let issue = Self.describe(error, context: .load)
            Task { await self?.recordError(issue) }
        }
        observers.add(tasksRef, tasksHandle)

        let connectedHandle = connectedRef.observe(.value) { @Sendable [weak self] snapshot in
            let connected = (snapshot.value as? Bool) ?? false
            Task { await self?.setConnected(connected) }
        }
        observers.add(connectedRef, connectedHandle)
    }

    /// Builds the wire payload and hands it to Firebase.
    ///
    /// A single multi-path update, so a reorder that touches several tasks cannot
    /// land half-applied.
    private nonisolated func enqueue(_ tasks: [BoardTask]) {
        var payload: [String: Any] = [:]
        for task in tasks {
            payload[task.id] = task.remoteValue
        }

        let ids = tasks.map(\.id)
        tasksRef.updateChildValues(payload) { @Sendable [weak self] error, _ in
            let issue = error.map { Self.describe($0, context: .write) }
            Task { await self?.completeWrite(ids: ids, issue: issue) }
        }
    }

    // MARK: - Event handling

    private func applyRemote(_ decoded: [BoardTask]) async {
        tasks = decoded

        if isConnected, !hasRoundTrippedWhileConnected {
            hasRoundTrippedWhileConnected = true
            // Firebase has replayed anything queued before this launch, so markers
            // restored from disk are no longer meaningful.
            await tracker.clearRestored()
            pendingIDs = await tracker.current
        }

        emit()
    }

    private func setConnected(_ connected: Bool) {
        guard connected != isConnected else { return }
        isConnected = connected
        if !connected { hasRoundTrippedWhileConnected = false }
        emit()
    }

    private func completeWrite(ids: [BoardTask.ID], issue: SyncIssue?) async {
        if let issue {
            // The write stays marked pending: it failed, the local copy is still
            // there, and saying so is more useful than quietly dropping the marker.
            lastError = issue
        } else {
            pendingIDs.subtract(ids)
            await tracker.markAcknowledged(ids)
        }
        emit()
    }

    private func recordError(_ issue: SyncIssue) {
        lastError = issue
        emit()
    }

    // MARK: - Streaming

    private func register(_ continuation: AsyncStream<RepositorySnapshot>.Continuation, id: UUID) {
        continuations[id] = continuation
        continuation.yield(snapshot())
    }

    private func unregister(_ id: UUID) {
        continuations[id] = nil
    }

    private func snapshot() -> RepositorySnapshot {
        RepositorySnapshot(
            tasks: tasks.sorted(by: BoardLogic.isOrderedBefore),
            sync: SyncSummary(isConnected: isConnected, lastError: lastError),
            pendingIDs: pendingIDs
        )
    }

    private func emit() {
        let current = snapshot()
        for continuation in continuations.values {
            continuation.yield(current)
        }
    }

    // MARK: - Errors

    private enum ErrorContext { case load, write }

    private static func describe(_ error: Error, context: ErrorContext) -> SyncIssue {
        let text = error.localizedDescription
        let repositoryError: RepositoryError = if text.localizedCaseInsensitiveContains("permission") {
            .permissionDenied
        } else {
            switch context {
            case .load: .loadFailed(text)
            case .write: .writeFailed(text)
            }
        }
        let message = repositoryError.errorDescription ?? text
        return switch context {
        case .load: .load(message)
        case .write: .write(message)
        }
    }
}

/// Holds Firebase observer registrations so they can be removed when the repository
/// goes away.
///
/// An actor cannot reach its own isolated state from `deinit` under Swift 6, so the
/// registrations live here and this object's own `deinit` — which runs without
/// isolation — does the teardown.
private final class ObserverRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var handles: [(DatabaseReference, DatabaseHandle)] = []

    func add(_ reference: DatabaseReference, _ handle: DatabaseHandle) {
        lock.lock()
        defer { lock.unlock() }
        handles.append((reference, handle))
    }

    deinit {
        for (reference, handle) in handles {
            reference.removeObserver(withHandle: handle)
        }
    }
}
