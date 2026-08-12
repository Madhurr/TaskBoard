import Foundation
import Observation

/// Drives the board. Owns presentation state; delegates rules to `BoardLogic` and
/// writes to a `TaskRepository`. The clock is injected so tests are deterministic.
@MainActor
@Observable
final class BoardViewModel {

    enum Phase: Equatable {
        case loading
        case ready
        /// Load failed with no cached data to fall back on.
        case failed(String)
    }

    /// One reversible step. Holding the previous versions covers deletes, edits,
    /// and moves with the same mechanism.
    struct UndoStep: Equatable {
        let label: String
        let previous: [BoardTask]
    }

    // MARK: - Observable state

    private(set) var snapshot: RepositorySnapshot = .empty
    private(set) var phase: Phase = .loading
    private(set) var undoStep: UndoStep?
    /// A write failed. The edit is still on screen and still saved locally.
    private(set) var writeError: String?

    var searchQuery: String = ""
    var statusFilter: Set<TaskStatus> = []

    // MARK: - Dependencies

    private let repository: any TaskRepository
    private let now: @Sendable () -> Date
    private let observation = ObservationTaskBox()

    init(repository: any TaskRepository, now: @escaping @Sendable () -> Date = { Date() }) {
        self.repository = repository
        self.now = now
    }

    // MARK: - Lifecycle

    /// Begins observing. Idempotent.
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

    /// Writes the repository hasn't echoed back yet. Snapshots arrive
    /// asynchronously, so without this the next edit would compute its position
    /// from stale data. Timestamps can't arbitrate — edits in the same tick share
    /// an `updatedAt`.
    private var localOverlay: [BoardTask.ID: BoardTask] = [:]

    private func apply(_ incoming: RepositorySnapshot) {
        var byID = Dictionary(incoming.tasks.map { ($0.id, $0) }, uniquingKeysWith: BoardLogic.resolve)

        for (id, pending) in localOverlay {
            if byID[id] == pending {
                // Caught up; stop shadowing so remote changes flow through again.
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

        // Only a load failure with nothing to show takes over the screen; a
        // rejected write leaves the board intact and belongs in the header.
        phase = if let issue = incoming.sync.lastError, issue.kind == .load, snapshot.tasks.isEmpty {
            .failed(issue.message)
        } else {
            .ready
        }

        writeError = incoming.sync.lastError.map(\.message) ?? writeError
    }

    /// Shows a write immediately, before it is persisted or acknowledged.
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

    /// Columns after search and status filtering.
    var columns: [(status: TaskStatus, tasks: [BoardTask])] {
        let visible = BoardLogic.filter(snapshot.tasks, query: searchQuery, statuses: statusFilter)
        return BoardLogic.columns(in: visible)
    }

    var isFiltering: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !statusFilter.isEmpty
    }

    /// Genuinely empty, as opposed to a filter hiding everything.
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

    /// `targetIndex` counts slots in the destination column, excluding the moved task.
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

        // Renumber in the same atomic write, so the board is never seen mid-rebalance.
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
            if let corrected = renumbered.first(where: { $0.id == id }) {
                writes[0] = corrected
            }
        }

        await write(writes, undoLabel: "Move undone", previous: previous)
    }

    func undo() async {
        guard let step = undoStep else { return }
        undoStep = nil

        // Fresh timestamp so the revert wins last-write-wins against what it undoes.
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

    /// Single funnel for every mutation. Never rolls the change back on failure:
    /// it is already durable locally and will be retried.
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
