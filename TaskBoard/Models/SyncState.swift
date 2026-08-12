import Foundation

/// Sync state of a single task.
enum SyncState: String, Sendable, Equatable {
    case synced
    case pending
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
struct SyncSummary: Equatable, Sendable {
    var isConnected: Bool
    var lastError: SyncIssue?

    static let initial = SyncSummary(isConnected: false, lastError: nil)

    func state(for taskID: BoardTask.ID, pendingIDs: Set<BoardTask.ID>) -> SyncState {
        guard pendingIDs.contains(taskID) else { return .synced }
        return isConnected ? .pending : .queuedOffline
    }
}

/// A sync failure. The kind decides how loudly the UI reports it: a failed read can
/// leave the board empty, a failed write leaves it intact.
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
