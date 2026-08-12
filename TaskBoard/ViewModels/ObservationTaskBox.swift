import Foundation

/// Owns a long-lived observation `Task` for an actor-isolated type.
///
/// A `@MainActor` class can't reach its own isolated state from `deinit`, so it
/// can't cancel a task it holds directly. This box's `deinit` runs unisolated and
/// does the teardown instead.
final class ObservationTaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Never>?

    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return task != nil
    }

    func set(_ newTask: Task<Void, Never>) {
        lock.lock()
        let previous = task
        task = newTask
        lock.unlock()
        previous?.cancel()
    }

    func cancel() {
        lock.lock()
        let current = task
        task = nil
        lock.unlock()
        current?.cancel()
    }

    deinit {
        task?.cancel()
    }
}
