import Foundation

/// In-memory `TaskRepository` used by tests, SwiftUI previews, and the in-app
/// debug mode.
///
/// It models the parts of the real backend that matter for behaviour — a durable
/// queue that holds writes while offline and replays them on reconnect — so the
/// offline story can be exercised deterministically, without a network, a
/// simulator toggle, or a Firebase project.
actor InMemoryTaskRepository: TaskRepository {

    /// Knobs for simulating a hostile network.
    struct Conditions: Sendable, Equatable {
        var isOnline: Bool = true
        /// Artificial round-trip delay applied before a write is acknowledged.
        var latency: Duration = .zero
        /// Fraction of writes the server rejects outright, 0...1.
        var failureRate: Double = 0
        /// When set, `start()` fails with this error.
        var loadError: RepositoryError?

        static let perfect = Conditions()
        static let offline = Conditions(isOnline: false)
    }

    private var tasks: [BoardTask.ID: BoardTask]
    private var conditions: Conditions
    private var pendingIDs: Set<BoardTask.ID> = []
    private var lastError: SyncIssue?
    private var hasStarted = false

    /// Writes accepted locally but not yet acknowledged, awaiting reconnection.
    private var queue: [BoardTask] = []

    private var continuations: [UUID: AsyncStream<RepositorySnapshot>.Continuation] = [:]

    /// Deterministic pseudo-random source, so an injected failure rate produces the
    /// same sequence in every test run.
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

        // Applied locally first and unconditionally — this is what makes the app
        // usable offline, and it must not depend on the outcome of the write.
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

    /// Test seam: the tasks currently held, in board order.
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
            // The local copy is kept: the user's work survives a failed write, and
            // the task stays marked pending so the failure is visible rather than
            // silently dropped.
            let error = RepositoryError.writeFailed("The server rejected the request.")
            lastError = .write(error.errorDescription ?? "The write was rejected.")
            emit()
            throw error
        }

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

    /// xorshift64*, so failure injection is reproducible across runs.
    private func nextRandom() -> Double {
        randomSeed ^= randomSeed >> 12
        randomSeed ^= randomSeed << 25
        randomSeed ^= randomSeed >> 27
        let value = randomSeed &* 0x2545F491_4F6CDD1D
        return Double(value >> 11) / Double(1 << 53)
    }
}
