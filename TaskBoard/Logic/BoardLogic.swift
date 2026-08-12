import Foundation

/// Pure board rules. No Firebase, no SwiftUI, no clock, no I/O — every function
/// here is a total function of its arguments, which is what makes the interesting
/// parts of this app testable without a network or a simulator.
enum BoardLogic {

    // MARK: - Fractional indexing

    /// Gap left between adjacent positions when appending.
    static let positionStep: Double = 1024

    /// Below this gap, `Double` starts losing the ability to subdivide reliably
    /// and the column should be renumbered.
    static let minimumGap: Double = 0.0001

    /// The position a task should take when inserted into `column` at `index`.
    ///
    /// `column` must be sorted ascending by position and must **not** contain the
    /// task being moved — the caller removes it first, so `index` always refers to
    /// a slot in the remaining items. `index` is clamped to `0...column.count`.
    ///
    /// Inserting between two neighbours splits the gap, so a move writes exactly
    /// one record. Renumbering the siblings instead would mean N queued writes per
    /// drag, which is precisely the wrong trade when those writes are offline.
    static func position(insertingInto column: [BoardTask], at index: Int) -> Double {
        let bounded = min(max(index, 0), column.count)

        let before: Double? = bounded > 0 ? column[bounded - 1].position : nil
        let after: Double? = bounded < column.count ? column[bounded].position : nil

        switch (before, after) {
        case (nil, nil):
            return 0
        case (nil, .some(let next)):
            return next - positionStep
        case (.some(let prev), nil):
            return prev + positionStep
        case (.some(let prev), .some(let next)):
            return prev + (next - prev) / 2
        }
    }

    /// True when any adjacent pair in `column` has been subdivided to the point
    /// that another split would be unsafe.
    static func needsRebalance(_ column: [BoardTask]) -> Bool {
        guard column.count > 1 else { return false }
        return zip(column, column.dropFirst()).contains { $0.position.distance(to: $1.position) < minimumGap }
    }

    /// Evenly renumbered copy of `column`, preserving visible order.
    /// Only the tasks whose position actually changed are returned, so the caller
    /// writes the minimum number of records.
    static func rebalanced(_ column: [BoardTask]) -> [BoardTask] {
        column.enumerated().compactMap { offset, task in
            let target = Double(offset) * positionStep
            guard task.position != target else { return nil }
            var copy = task
            copy.position = target
            return copy
        }
    }

    // MARK: - Grouping

    /// Live tasks for `status`, sorted into display order.
    ///
    /// Ties on `position` are broken by `createdAt` then `id` so that the order is
    /// total and stable: two devices that independently land on the same position
    /// still render the column identically.
    static func column(_ status: TaskStatus, in tasks: [BoardTask]) -> [BoardTask] {
        tasks
            .filter { !$0.isDeleted && $0.status == status }
            .sorted(by: isOrderedBefore)
    }

    /// All three columns in display order.
    static func columns(in tasks: [BoardTask]) -> [(status: TaskStatus, tasks: [BoardTask])] {
        TaskStatus.ordered.map { ($0, column($0, in: tasks)) }
    }

    static func isOrderedBefore(_ lhs: BoardTask, _ rhs: BoardTask) -> Bool {
        if lhs.position != rhs.position { return lhs.position < rhs.position }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id < rhs.id
    }

    // MARK: - Moving

    /// The updated task produced by dropping `taskID` into `status` at `targetIndex`.
    ///
    /// Returns `nil` when the task is unknown, deleted, or already exactly where it
    /// was asked to go — the caller can then skip the write entirely rather than
    /// queueing a no-op mutation.
    static func move(
        taskID: BoardTask.ID,
        to status: TaskStatus,
        targetIndex: Int,
        in tasks: [BoardTask],
        now: Date
    ) -> BoardTask? {
        guard let task = tasks.first(where: { $0.id == taskID }), !task.isDeleted else { return nil }

        let destination = column(status, in: tasks).filter { $0.id != taskID }
        let newPosition = position(insertingInto: destination, at: targetIndex)

        guard task.status != status || task.position != newPosition else { return nil }

        var moved = task
        moved.status = status
        moved.position = newPosition
        moved.updatedAt = now
        return moved
    }

    // MARK: - Search & filter

    /// Case- and diacritic-insensitive match across title and details.
    static func filter(_ tasks: [BoardTask], query: String, statuses: Set<TaskStatus>) -> [BoardTask] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return tasks.filter { task in
            guard !task.isDeleted else { return false }
            guard statuses.isEmpty || statuses.contains(task.status) else { return false }
            guard !needle.isEmpty else { return true }
            return task.title.matches(needle) || task.details.matches(needle)
        }
    }

    // MARK: - Conflict resolution

    /// Last-write-wins on `updatedAt`, with `id` as a deterministic tiebreak.
    ///
    /// Two devices that edit the same task offline both replay their writes on
    /// reconnect, and Realtime Database resolves that by arrival order — the slower
    /// network wins, which is not what anyone means by "latest". Comparing
    /// `updatedAt` makes the outcome depend on when the edit happened instead, and
    /// the same comparison is enforced server-side in `database.rules.json` so a
    /// stale write is rejected rather than merely ignored on one client.
    static func resolve(local: BoardTask, remote: BoardTask) -> BoardTask {
        if local.updatedAt != remote.updatedAt {
            return local.updatedAt > remote.updatedAt ? local : remote
        }
        // Same instant: a deletion is the more conservative outcome to keep.
        if local.isDeleted != remote.isDeleted {
            return local.isDeleted ? local : remote
        }
        // Still tied. The tiebreak must be derived from the *content*: both sides
        // are versions of one task and therefore share an id, so comparing ids
        // would collapse to "always prefer local" and the two devices would each
        // keep their own copy forever.
        return local.conflictTiebreakKey <= remote.conflictTiebreakKey ? local : remote
    }

    /// Applies `resolve` across two full snapshots, keyed by id.
    static func merge(local: [BoardTask], remote: [BoardTask]) -> [BoardTask] {
        var byID = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: resolve)
        for task in remote {
            byID[task.id] = byID[task.id].map { resolve(local: $0, remote: task) } ?? task
        }
        return byID.values.sorted(by: isOrderedBefore)
    }

    // MARK: - Validation

    /// A task with an empty title is not worth persisting, offline or otherwise.
    static func isValid(title: String) -> Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private extension String {
    func matches(_ needle: String) -> Bool {
        range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
