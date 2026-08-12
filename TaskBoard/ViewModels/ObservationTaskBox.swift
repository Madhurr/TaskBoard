import Foundation

/// Owns a long-lived observation `Task` on behalf of an actor-isolated type.
///
/// Under Swift 6, a `@MainActor` class cannot reach its own isolated stored
/// properties from `deinit`, so it cannot cancel a task it holds directly. Parking
/// the task in a `Sendable` box moves the teardown into the box's own `deinit`,
/// which runs without isolation — the task is cancelled when its owner goes away,
/// with no unchecked escape hatch on the owner itself.
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
