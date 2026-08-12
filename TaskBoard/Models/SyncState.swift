import Foundation

/// Per-task sync visibility.
///
/// Firebase's own write queue is durable and replays on reconnect, but it exposes
/// no per-record view of what is still in flight. This mirrors that queue for
/// display purposes only — it never gates, retries, or reorders a write.
enum SyncState: String, Sendable, Equatable {
    /// Acknowledged by the server.
    case synced
    /// Written locally, waiting on a server ack while the connection is up.
    case pending
    /// Written locally and parked in Firebase's queue until connectivity returns.
    case queuedOffline

    var symbolName: String? {
        switch self {
        case .synced: nil
        case .pending: "arrow.trianglehead.2.clockwise"
        case .queuedOffline: "cloud.slash"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .synced: "Synced"
        case .pending: "Syncing"
        case .queuedOffline: "Waiting for connection"
        }
    }
}

/// Board-wide connection state, driven by `.info/connected`.
///
/// Deliberately does *not* carry a count of outstanding writes. The set of pending
/// task ids already encodes that, and holding both invites them to disagree — which
/// shows up as a card badged "synced" while the toolbar still claims work is in
/// flight. The count is derived from the set on `RepositorySnapshot` instead.
struct SyncSummary: Equatable, Sendable {
    var isConnected: Bool
    /// Set when the last attempted sync surfaced an error worth showing.
    var lastError: SyncIssue?

    static let initial = SyncSummary(isConnected: false, lastError: nil)

    func state(for taskID: BoardTask.ID, pendingIDs: Set<BoardTask.ID>) -> SyncState {
        guard pendingIDs.contains(taskID) else { return .synced }
        return isConnected ? .pending : .queuedOffline
    }
}

/// A sync failure, tagged with which half of the exchange it came from.
///
/// The distinction is load-bearing for the UI: failing to *read* the board can
/// leave the user with nothing to look at and warrants taking over the screen,
/// whereas failing to *write* leaves everything on screen and intact and warrants
/// only a line in the header. Collapsing both into one string produced exactly the
/// wrong pairing — a rejected write reported under "Couldn't load your board".
struct SyncIssue: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case load
        case write
    }

    var kind: Kind
    var message: String

    static func load(_ message: String) -> SyncIssue { SyncIssue(kind: .load, message: message) }
    static func write(_ message: String) -> SyncIssue { SyncIssue(kind: .write, message: message) }
}
