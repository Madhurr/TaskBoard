import Foundation

/// In-memory `TaskRepository` for tests, previews, and the developer sheet.
/// Models a durable offline queue that replays on reconnect.
actor InMemoryTaskRepository: TaskRepository {

    /// Simulated network conditions.
    struct Conditions: Sendable, Equatable {
        var isOnline: Bool = true
        /// Delay before a write is acknowledged.
        var latency: Duration = .zero
        /// Fraction of writes rejected, 0...1.
        var failureRate: Double = 0
        /// When set, `start()` reports this error.
        var loadError: RepositoryError?

        static let perfect = Conditions()
        static let offline = Conditions(isOnline: false)
    }

    private var tasks: [BoardTask.ID: BoardTask]
    private var conditions: Conditions
    private var pendingIDs: Set<BoardTask.ID> = []
    private var lastError: SyncIssue?
    private var hasStarted = false

    /// Accepted locally, waiting on reconnection.
    private var queue: [BoardTask] = []

    private var continuations: [UUID: AsyncStream<RepositorySnapshot>.Continuation] = [:]

    /// Seeded so failure injection repeats across runs.
    private var randomSeed: UInt64

    init(tasks: [BoardTask] = [], conditions: Conditions = .perfect, seed: UInt64 = 0x2545F491_4F6CDD1D) {
        self.tasks = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        self.conditions = conditions
        self.randomSeed = seed
    }

    // MARK: - TaskRepository

    nonisolated func snapshots() -> AsyncStream<RepositorySnapshot> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.register(continuation, id: id) }
            continuation.onTermination = { _ in
                Task { await self.unregister(id) }
            }
        }
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true

        if let loadError = conditions.loadError {
            lastError = .load(loadError.errorDescription ?? "Couldn't reach the server.")
        }
        emit()
    }

    func save(_ incoming: [BoardTask]) async throws {
        guard !incoming.isEmpty else { return }

        // Applied locally first, regardless of the write's outcome.
        for task in incoming {
            tasks[task.id] = task
            pendingIDs.insert(task.id)
        }
        lastError = nil
        emit()

        guard conditions.isOnline else {
            queue.append(contentsOf: incoming)
            return
        }

        try await acknowledge(incoming)
    }

    func clearError() async {
        lastError = nil
        emit()
    }

    // MARK: - Debug controls

    func setConditions(_ new: Conditions) async {
        let wasOffline = !conditions.isOnline
        conditions = new
        emit()

        if wasOffline && new.isOnline {
            await flushQueue()
        }
    }

    var currentConditions: Conditions { conditions }

    var storedTasks: [BoardTask] {
        tasks.values.sorted(by: BoardLogic.isOrderedBefore)
    }

    var outstandingWrites: Int { pendingIDs.count }

    // MARK: - Internals

    private func acknowledge(_ written: [BoardTask]) async throws {
        if conditions.latency > .zero {
            try? await Task.sleep(for: conditions.latency)
        }

        if conditions.failureRate > 0, nextRandom() < conditions.failureRate {
            // Keep the local copy and stay pending, so the failure is visible.
            let error = RepositoryError.writeFailed("The server rejected the request.")
            lastError = .write(error.errorDescription ?? "The write was rejected.")
            emit()
            throw error
        }

        // Re-check: the task may have been edited again while this was in flight.
        for task in written where tasks[task.id]?.updatedAt == task.updatedAt {
            pendingIDs.remove(task.id)
        }
        emit()
    }

    private func flushQueue() async {
        let replay = queue
        queue.removeAll()
        guard !replay.isEmpty else { return }
        try? await acknowledge(replay)
    }

    private func register(_ continuation: AsyncStream<RepositorySnapshot>.Continuation, id: UUID) {
        continuations[id] = continuation
        continuation.yield(snapshot())
    }

    private func unregister(_ id: UUID) {
        continuations[id] = nil
    }

    private func snapshot() -> RepositorySnapshot {
        RepositorySnapshot(
            tasks: tasks.values.sorted(by: BoardLogic.isOrderedBefore),
            sync: SyncSummary(isConnected: conditions.isOnline, lastError: lastError),
            pendingIDs: pendingIDs
        )
    }

    private func emit() {
        let current = snapshot()
        for continuation in continuations.values {
            continuation.yield(current)
        }
    }

    /// xorshift64*
    private func nextRandom() -> Double {
        randomSeed ^= randomSeed >> 12
        randomSeed ^= randomSeed << 25
        randomSeed ^= randomSeed >> 27
        let value = randomSeed &* 0x2545F491_4F6CDD1D
        return Double(value >> 11) / Double(1 << 53)
    }
}
