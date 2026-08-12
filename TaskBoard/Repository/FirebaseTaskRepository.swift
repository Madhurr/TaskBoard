import FirebaseDatabase
import Foundation

/// Realtime Database backed `TaskRepository`.
///
/// With persistence enabled the local cache is the store: reads come from it at
/// launch, writes are applied synchronously and queued durably across launches.
/// `PendingWriteTracker` mirrors that queue for the UI, which Firebase doesn't expose.
actor FirebaseTaskRepository: TaskRepository {

    // Firebase references are thread-safe. They're reachable from the nonisolated
    // methods below, which exist because a closure formed in actor-isolated code
    // captures that isolation and can't be handed to a callback-based API.
    private nonisolated(unsafe) let tasksRef: DatabaseReference
    private nonisolated(unsafe) let connectedRef: DatabaseReference

    private let tracker: PendingWriteTracker
    private let observers = ObserverRegistry()

    private var tasks: [BoardTask] = []
    private var pendingIDs: Set<BoardTask.ID> = []
    private var isConnected = false
    private var lastError: SyncIssue?

    private var hasStarted = false
    /// True once a value event has arrived while connected — by then Firebase has
    /// replayed anything queued from a previous launch.
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
    /// Does not await the server: the completion handler fires only on
    /// acknowledgement, which offline never comes. It's handled out of band and
    /// surfaces as a change in `pendingIDs`.
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
        // Keeps the node cached so a cold launch has data without the network.
        tasksRef.keepSynced(true)

        let tasksHandle = tasksRef.observe(.value) { @Sendable [weak self] snapshot in
            // Decode here so only Sendable values cross into the actor.
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

    /// One multi-path update, so a reorder touching several tasks can't half-apply.
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
            // Stays pending: the local copy is still there and the failure is worth showing.
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

/// Holds observer registrations so they can be removed on teardown. An actor can't
/// reach its own isolated state from `deinit`, so they live here instead.
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
