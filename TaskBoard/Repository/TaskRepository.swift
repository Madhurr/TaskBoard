import Foundation

/// Everything the board needs to render, delivered as one value.
///
/// The task list and the sync indicators travel together on purpose: emitting them
/// on separate streams lets the UI show a card as synced in the same frame that the
/// summary still counts it as pending, and that tearing is exactly the kind of thing
/// a user reads as "the app is lying to me about my data".
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

    /// True when there is nothing worth interrupting the user about.
    var isQuiet: Bool { sync.isConnected && pendingIDs.isEmpty && sync.lastError == nil }
}

/// Persistence and sync, as the rest of the app sees it.
///
/// `save` deliberately returns as soon as the write is durable *locally*. Awaiting
/// the server acknowledgement would mean every offline edit hangs until connectivity
/// returns, which inverts the whole point of the app; the acknowledgement instead
/// arrives out of band and shows up as a change in `pendingIDs`.
protocol TaskRepository: Sendable {
    /// Snapshots, beginning with whatever is already on disk. Emits on every local
    /// mutation, every remote change, and every connectivity transition.
    func snapshots() -> AsyncStream<RepositorySnapshot>

    /// Begins observing. Safe to call more than once.
    func start() async

    /// Writes tasks locally and queues them for the server. Multiple tasks are
    /// written as a single atomic update so a reorder cannot land half-applied.
    func save(_ tasks: [BoardTask]) async throws

    /// Clears a surfaced error after the user has acknowledged it.
    func clearError() async
}

extension TaskRepository {
    func save(_ task: BoardTask) async throws {
        try await save([task])
    }
}

/// Failures worth telling the user about.
enum RepositoryError: LocalizedError, Equatable {
    case notConfigured(String)
    case writeFailed(String)
    case loadFailed(String)
    case permissionDenied
    /// The server rejected a write because a newer version of the task already
    /// exists — see the `updatedAt` guard in `database.rules.json`.
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

    /// Whether the user's work is still safe. Only a genuine rejection loses data;
    /// everything else is retried from Firebase's durable queue.
    var isRecoverable: Bool {
        switch self {
        case .staleWrite, .permissionDenied, .notConfigured: false
        case .writeFailed, .loadFailed: true
        }
    }
}
