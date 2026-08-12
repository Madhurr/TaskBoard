import Foundation

/// Everything the board needs to render, in one value so the task list and the
/// sync indicators can't disagree.
struct RepositorySnapshot: Sendable, Equatable {
    var tasks: [BoardTask]
    var sync: SyncSummary
    var pendingIDs: Set<BoardTask.ID>

    static let empty = RepositorySnapshot(tasks: [], sync: .initial, pendingIDs: [])

    func syncState(for id: BoardTask.ID) -> SyncState {
        sync.state(for: id, pendingIDs: pendingIDs)
    }

    var pendingCount: Int { pendingIDs.count }

    var hasPendingWork: Bool { !pendingIDs.isEmpty }

    var isQuiet: Bool { sync.isConnected && pendingIDs.isEmpty && sync.lastError == nil }
}

/// Persistence and sync, as the rest of the app sees it.
protocol TaskRepository: Sendable {
    /// Snapshots, starting with whatever is cached locally.
    func snapshots() -> AsyncStream<RepositorySnapshot>

    /// Begins observing. Safe to call more than once.
    func start() async

    /// Writes locally and queues for the server. Returns once the write is durable
    /// locally — it does not wait for the server, which offline never answers.
    /// Multiple tasks go as one atomic update so a reorder can't half-apply.
    func save(_ tasks: [BoardTask]) async throws

    func clearError() async
}

extension TaskRepository {
    func save(_ task: BoardTask) async throws {
        try await save([task])
    }
}

enum RepositoryError: LocalizedError, Equatable {
    case notConfigured(String)
    case writeFailed(String)
    case loadFailed(String)
    case permissionDenied
    /// Rejected by the `updatedAt` guard in `database.rules.json`.
    case staleWrite

    var errorDescription: String? {
        switch self {
        case .notConfigured(let detail):
            "Task Board isn't configured yet. \(detail)"
        case .writeFailed(let detail):
            "Couldn't save your change. \(detail)"
        case .loadFailed(let detail):
            "Couldn't load your board. \(detail)"
        case .permissionDenied:
            "The server rejected this change. Check your database rules."
        case .staleWrite:
            "A newer version of this task already exists, so your change wasn't applied."
        }
    }

    /// False when the write will never succeed on retry.
    var isRecoverable: Bool {
        switch self {
        case .staleWrite, .permissionDenied, .notConfigured: false
        case .writeFailed, .loadFailed: true
        }
    }
}
