import Foundation

/// A single task on the board.
///
/// The identifier is generated on-device so that a task created while offline is
/// complete and addressable immediately — no server round-trip is needed to learn
/// its key, which is what lets edits and moves stack up on a task that the backend
/// has never seen.
struct BoardTask: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var title: String
    var details: String
    var status: TaskStatus
    /// Fractional index. Ordering within a column is ascending by `position`.
    var position: Double
    var createdAt: Date
    var updatedAt: Date
    /// Soft delete. Hard deletes race badly with offline replay — a queued update
    /// can resurrect a removed node — and a tombstone is what makes undo cheap.
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

    /// A stable, content-derived ordering key used only to break a conflict where
    /// two versions of this task carry the same `updatedAt`.
    ///
    /// Every field that can still differ at that point is included, so equal keys
    /// mean equal tasks and the comparison is a true total order. Doubles go in as
    /// bit patterns rather than formatted text to keep the encoding exact, and
    /// `hashValue` is avoided deliberately — Swift seeds it per process, so two
    /// devices would disagree about the winner.
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
