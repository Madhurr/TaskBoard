import Foundation
import Observation

/// Drives the board. Owns presentation state; delegates every rule to `BoardLogic`
/// and every write to a `TaskRepository`.
///
/// The clock is injected rather than read from `Date()` so that ordering, undo, and
/// conflict behaviour are all reproducible under test.
@MainActor
@Observable
final class BoardViewModel {

    /// What the board should be showing right now.
    enum Phase: Equatable {
        /// Nothing has arrived yet — not even the local cache.
        case loading
        case ready
        /// The initial load failed and there is no cached data to fall back on.
        case failed(String)
    }

    /// A single reversible step. Holding the *previous* versions of the affected
    /// tasks makes one mechanism cover deletes, edits, and moves alike.
    struct UndoStep: Equatable {
        let label: String
        let previous: [BoardTask]
    }

    // MARK: - Observable state

    private(set) var snapshot: RepositorySnapshot = .empty
    private(set) var phase: Phase = .loading
    private(set) var undoStep: UndoStep?
    /// Set when a write fails. The user's edit is still on screen and still saved
    /// locally — this only reports that the server has not taken it yet.
    private(set) var writeError: String?

    var searchQuery: String = ""
    var statusFilter: Set<TaskStatus> = []

    // MARK: - Dependencies

    private let repository: any TaskRepository
    private let now: @Sendable () -> Date
    /// Holds the observation task. A plain stored property would not do: a
    /// `@MainActor` type cannot touch its own isolated state from `deinit`, so the
    /// cancellation lives in a box that tears itself down instead.
    private let observation = ObservationTaskBox()

    init(repository: any TaskRepository, now: @escaping @Sendable () -> Date = { Date() }) {
        self.repository = repository
        self.now = now
    }

    // MARK: - Lifecycle

    /// Begins observing. Idempotent — calling it again while already running does
    /// nothing, so it is safe to drive from `onAppear`.
    func start() {
        guard !observation.isActive else { return }
        let stream = repository.snapshots()
        observation.set(
            Task { [weak self] in
                guard let self else { return }
                await repository.start()
                for await snapshot in stream {
                    guard !Task.isCancelled else { return }
                    self.apply(snapshot)
                }
            }
        )
    }

    func stop() {
        observation.cancel()
    }

    /// Local writes the repository has not echoed back yet.
    ///
    /// Snapshots arrive asynchronously, so between issuing a write and seeing it
    /// return there is a window where the stream still describes the old world. Two
    /// things go wrong without an overlay: a snapshot emitted just before the write
    /// lands flickers the previous value back onto the screen, and — worse — the
    /// next edit computes its position from stale data, which is how three quick
    /// taps on "add" ended up in arbitrary order.
    ///
    /// Timestamps cannot arbitrate this. Two edits within the same clock tick carry
    /// the same `updatedAt`, so last-write-wins has nothing to compare. Tracking
    /// which writes are still in flight does not need to guess.
    private var localOverlay: [BoardTask.ID: BoardTask] = [:]

    private func apply(_ incoming: RepositorySnapshot) {
        var byID = Dictionary(incoming.tasks.map { ($0.id, $0) }, uniquingKeysWith: BoardLogic.resolve)

        for (id, pending) in localOverlay {
            if byID[id] == pending {
                // The repository has caught up; stop shadowing this task so genuine
                // remote changes can flow through again.
                localOverlay[id] = nil
            } else {
                byID[id] = pending
            }
        }

        snapshot = RepositorySnapshot(
            tasks: byID.values.sorted(by: BoardLogic.isOrderedBefore),
            sync: incoming.sync,
            pendingIDs: incoming.pendingIDs.union(localOverlay.keys)
        )

        // Only a *load* failure takes over the screen, and only when there is
        // genuinely nothing to show. A rejected write leaves the board intact, so
        // reporting it as "couldn't load your board" would be both alarming and
        // false; it belongs in the header instead.
        phase = if let issue = incoming.sync.lastError, issue.kind == .load, snapshot.tasks.isEmpty {
            .failed(issue.message)
        } else {
            .ready
        }

        writeError = incoming.sync.lastError.map(\.message) ?? writeError
    }

    /// Shows a write on screen the instant it is issued, before it has been
    /// persisted or acknowledged. The local copy simply wins — it is the user's
    /// most recent intent, and nothing else in the system knows better yet.
    private func applyOptimistically(_ tasks: [BoardTask]) {
        var byID = Dictionary(snapshot.tasks.map { ($0.id, $0) }, uniquingKeysWith: BoardLogic.resolve)
        for task in tasks {
            byID[task.id] = task
            localOverlay[task.id] = task
        }

        snapshot = RepositorySnapshot(
            tasks: byID.values.sorted(by: BoardLogic.isOrderedBefore),
            sync: snapshot.sync,
            pendingIDs: snapshot.pendingIDs.union(tasks.map(\.id))
        )
    }

    // MARK: - Derived view state

    /// Columns after search and status filtering, in display order.
    var columns: [(status: TaskStatus, tasks: [BoardTask])] {
        let visible = BoardLogic.filter(snapshot.tasks, query: searchQuery, statuses: statusFilter)
        return BoardLogic.columns(in: visible)
    }

    var isFiltering: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !statusFilter.isEmpty
    }

    /// True only when the board is genuinely empty, not when a filter hid everything.
    var isBoardEmpty: Bool {
        snapshot.tasks.allSatisfy(\.isDeleted)
    }

    var hasNoMatches: Bool {
        isFiltering && columns.allSatisfy { $0.tasks.isEmpty } && !isBoardEmpty
    }

    func syncState(for task: BoardTask) -> SyncState {
        snapshot.syncState(for: task.id)
    }

    func task(_ id: BoardTask.ID) -> BoardTask? {
        snapshot.tasks.first { $0.id == id }
    }

    // MARK: - Mutations

    @discardableResult
    func createTask(title: String, details: String = "", status: TaskStatus = .todo) async -> BoardTask? {
        guard BoardLogic.isValid(title: title) else { return nil }

        let timestamp = now()
        let column = BoardLogic.column(status, in: snapshot.tasks)
        let task = BoardTask(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            details: details,
            status: status,
            position: BoardLogic.position(insertingInto: column, at: column.count),
            createdAt: timestamp,
            updatedAt: timestamp
        )

        await write([task], undoLabel: nil)
        return task
    }

    func updateTask(_ id: BoardTask.ID, title: String, details: String) async {
        guard let existing = task(id), BoardLogic.isValid(title: title) else { return }

        var updated = existing
        updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.details = details
        updated.updatedAt = now()

        guard updated != existing else { return }
        await write([updated], undoLabel: "Edit undone", previous: [existing])
    }

    func delete(_ id: BoardTask.ID) async {
        guard let existing = task(id), !existing.isDeleted else { return }

        var tombstone = existing
        tombstone.isDeleted = true
        tombstone.updatedAt = now()

        await write([tombstone], undoLabel: "Task restored", previous: [existing])
    }

    /// Moves a task into `status` at `targetIndex`, where the index counts slots in
    /// the destination column with the moved task already excluded.
    func move(_ id: BoardTask.ID, to status: TaskStatus, targetIndex: Int) async {
        guard let existing = task(id),
              let moved = BoardLogic.move(
                  taskID: id,
                  to: status,
                  targetIndex: targetIndex,
                  in: snapshot.tasks,
                  now: now()
              )
        else { return }

        var writes = [moved]
        var previous = [existing]

        // Subdividing the same gap repeatedly eventually exhausts Double's
        // precision. Renumber the column in the same atomic write so the board is
        // never observed mid-rebalance.
        var projected = snapshot.tasks.filter { $0.id != id }
        projected.append(moved)
        let destination = BoardLogic.column(status, in: projected)

        if BoardLogic.needsRebalance(destination) {
            let renumbered = BoardLogic.rebalanced(destination).map { task -> BoardTask in
                var copy = task
                copy.updatedAt = now()
                return copy
            }
            let alreadyWriting = Set(writes.map(\.id))
            for task in renumbered where !alreadyWriting.contains(task.id) {
                writes.append(task)
                if let original = self.task(task.id) { previous.append(original) }
            }
            // The moved task may itself have been renumbered.
            if let corrected = renumbered.first(where: { $0.id == id }) {
                writes[0] = corrected
            }
        }

        await write(writes, undoLabel: "Move undone", previous: previous)
    }

    func undo() async {
        guard let step = undoStep else { return }
        undoStep = nil

        // Restored with a fresh timestamp so the revert wins last-write-wins
        // against the change it is undoing, including on other devices.
        let timestamp = now()
        let restored = step.previous.map { task -> BoardTask in
            var copy = task
            copy.updatedAt = timestamp
            return copy
        }

        await write(restored, undoLabel: nil)
    }

    func dismissUndo() {
        undoStep = nil
    }

    func dismissError() async {
        writeError = nil
        await repository.clearError()
    }

    func clearFilters() {
        searchQuery = ""
        statusFilter.removeAll()
    }

    func toggleFilter(_ status: TaskStatus) {
        if statusFilter.contains(status) {
            statusFilter.remove(status)
        } else {
            statusFilter.insert(status)
        }
    }

    // MARK: - Write path

    /// Single funnel for every mutation: publish the undo step, persist, and turn a
    /// failure into a message without ever rolling the user's change back.
    ///
    /// Rolling back on failure would be the wrong call here. The write is already
    /// durable locally and Firebase will retry it; discarding it on screen would
    /// throw away work the app has, in fact, kept.
    private func write(_ tasks: [BoardTask], undoLabel: String?, previous: [BoardTask] = []) async {
        guard !tasks.isEmpty else { return }

        if let undoLabel, !previous.isEmpty {
            undoStep = UndoStep(label: undoLabel, previous: previous)
        }

        applyOptimistically(tasks)

        do {
            writeError = nil
            try await repository.save(tasks)
        } catch let error as RepositoryError {
            writeError = error.errorDescription
        } catch {
            writeError = RepositoryError.writeFailed(error.localizedDescription).errorDescription
        }
    }
}
