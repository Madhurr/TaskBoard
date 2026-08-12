import Foundation

/// A single task on the board. Ids are generated on-device so a task created
/// offline is usable before the server has ever seen it.
struct BoardTask: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var title: String
    var details: String
    var status: TaskStatus
    /// Fractional index; columns sort ascending by this.
    var position: Double
    var createdAt: Date
    var updatedAt: Date
    /// Soft delete, so offline replay can't resurrect a removed task.
    var isDeleted: Bool

    init(
        id: String = UUID().uuidString,
        title: String,
        details: String = "",
        status: TaskStatus = .todo,
        position: Double,
        createdAt: Date,
        updatedAt: Date,
        isDeleted: Bool = false
    ) {
        self.id = id
        self.title = title
        self.details = details
        self.status = status
        self.position = position
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
    }
}

extension BoardTask {
    var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasDetails: Bool {
        !details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Tiebreak for two versions of this task with the same `updatedAt`.
    ///
    /// Covers every field that can still differ, so equal keys mean equal tasks.
    /// Not `hashValue`: that is seeded per process and would differ across devices.
    var conflictTiebreakKey: String {
        [
            title,
            details,
            status.rawValue,
            String(position.bitPattern),
            String(createdAt.timeIntervalSince1970.bitPattern),
        ].joined(separator: "\u{1}")
    }
}
