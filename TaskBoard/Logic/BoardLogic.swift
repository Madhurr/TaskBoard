import Foundation

/// Pure board rules — no Firebase, SwiftUI, clock, or I/O.
enum BoardLogic {

    // MARK: - Fractional indexing

    /// Gap left between adjacent positions when appending.
    static let positionStep: Double = 1024

    /// Below this gap `Double` can no longer subdivide reliably.
    static let minimumGap: Double = 0.0001

    /// Position for a task inserted into `column` at `index`.
    ///
    /// `column` must be sorted by position and must not contain the task being
    /// moved. `index` is clamped to `0...column.count`.
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

    /// True when some adjacent pair is too close to subdivide again.
    static func needsRebalance(_ column: [BoardTask]) -> Bool {
        guard column.count > 1 else { return false }
        return zip(column, column.dropFirst()).contains { $0.position.distance(to: $1.position) < minimumGap }
    }

    /// Evenly renumbered `column`, returning only the tasks that actually changed.
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

    /// Live tasks for `status`, in display order.
    static func column(_ status: TaskStatus, in tasks: [BoardTask]) -> [BoardTask] {
        tasks
            .filter { !$0.isDeleted && $0.status == status }
            .sorted(by: isOrderedBefore)
    }

    static func columns(in tasks: [BoardTask]) -> [(status: TaskStatus, tasks: [BoardTask])] {
        TaskStatus.ordered.map { ($0, column($0, in: tasks)) }
    }

    /// Total order, so devices that land on the same position still agree.
    static func isOrderedBefore(_ lhs: BoardTask, _ rhs: BoardTask) -> Bool {
        if lhs.position != rhs.position { return lhs.position < rhs.position }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id < rhs.id
    }

    // MARK: - Moving

    /// Updated task for dropping `taskID` into `status` at `targetIndex`.
    /// Returns `nil` if unknown, deleted, or already there, so callers can skip
    /// the write.
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

    /// Last-write-wins on `updatedAt`. The same comparison is enforced in
    /// `database.rules.json`, so a stale write is rejected server-side too.
    static func resolve(local: BoardTask, remote: BoardTask) -> BoardTask {
        if local.updatedAt != remote.updatedAt {
            return local.updatedAt > remote.updatedAt ? local : remote
        }
        // Same instant: keep the deletion.
        if local.isDeleted != remote.isDeleted {
            return local.isDeleted ? local : remote
        }
        // Both sides share an id, so the tiebreak has to come from the content.
        return local.conflictTiebreakKey <= remote.conflictTiebreakKey ? local : remote
    }

    /// Applies `resolve` across two snapshots, keyed by id.
    static func merge(local: [BoardTask], remote: [BoardTask]) -> [BoardTask] {
        var byID = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: resolve)
        for task in remote {
            byID[task.id] = byID[task.id].map { resolve(local: $0, remote: task) } ?? task
        }
        return byID.values.sorted(by: isOrderedBefore)
    }

    // MARK: - Validation

    static func isValid(title: String) -> Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private extension String {
    func matches(_ needle: String) -> Bool {
        range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
