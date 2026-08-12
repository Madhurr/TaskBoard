import Foundation

/// Wire format for Realtime Database.
///
/// Hand-rolled rather than `Codable`: RTDB hands back `[String: Any]` full of
/// `NSNumber`s, and the decoding has to be total — one malformed record written by
/// an older build, or by a hand edit in the Firebase console, must not take the
/// whole board down with it.
extension BoardTask {

    /// Keys are the wire contract. Renaming one is a migration, not a refactor —
    /// `updatedAt` in particular is also referenced by `database.rules.json`.
    enum Key {
        static let id = "id"
        static let title = "title"
        static let details = "details"
        static let status = "status"
        static let position = "position"
        static let createdAt = "createdAt"
        static let updatedAt = "updatedAt"
        static let isDeleted = "isDeleted"
    }

    var remoteValue: [String: Any] {
        [
            Key.id: id,
            Key.title: title,
            Key.details: details,
            Key.status: status.rawValue,
            Key.position: position,
            // Milliseconds since epoch: the unit Realtime Database uses for
            // `ServerValue.timestamp()`, so client and server stamps stay comparable
            // and the security rule can order them.
            Key.createdAt: createdAt.millisecondsSince1970,
            Key.updatedAt: updatedAt.millisecondsSince1970,
            Key.isDeleted: isDeleted,
        ]
    }

    /// Returns `nil` for a record that cannot be trusted. Callers skip those rather
    /// than substituting defaults, so a corrupt row is invisible instead of
    /// silently wrong.
    init?(remoteValue: Any, fallbackID: String) {
        guard let dict = remoteValue as? [String: Any] else { return nil }

        let id = (dict[Key.id] as? String) ?? fallbackID
        guard !id.isEmpty else { return nil }

        guard let title = dict[Key.title] as? String else { return nil }

        // Anything unrecognised lands in To Do rather than vanishing from the board.
        let status = (dict[Key.status] as? String).flatMap(TaskStatus.init(rawValue:)) ?? .todo

        let position = (dict[Key.position] as? NSNumber)?.doubleValue ?? 0
        let createdAt = (dict[Key.createdAt] as? NSNumber)?.dateFromMilliseconds ?? .distantPast
        let updatedAt = (dict[Key.updatedAt] as? NSNumber)?.dateFromMilliseconds ?? createdAt

        self.init(
            id: id,
            title: title,
            details: (dict[Key.details] as? String) ?? "",
            status: status,
            position: position,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isDeleted: (dict[Key.isDeleted] as? Bool) ?? false
        )
    }

    /// Decodes the whole `tasks` node, dropping records that fail to parse.
    static func decodeAll(from value: Any?) -> [BoardTask] {
        guard let node = value as? [String: Any] else { return [] }
        return node.compactMap { key, value in
            BoardTask(remoteValue: value, fallbackID: key)
        }
    }
}

extension Date {
    var millisecondsSince1970: Double {
        (timeIntervalSince1970 * 1000).rounded()
    }
}

private extension NSNumber {
    var dateFromMilliseconds: Date {
        Date(timeIntervalSince1970: doubleValue / 1000)
    }
}
