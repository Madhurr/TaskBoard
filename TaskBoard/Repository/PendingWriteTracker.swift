import Foundation

/// Tracks which task ids have a write in flight, so the UI can show per-task sync
/// state. Display only — Firebase owns the actual queue and retries.
///
/// Firebase's completion handlers don't survive process death, so the set is
/// persisted and cleared on the first round-trip after reconnect. That heuristic
/// can over-report briefly; it never under-reports.
actor PendingWriteTracker {

    private let defaultsKey = "pendingWriteIDs"
    private let defaults: UserDefaults

    private var ids: Set<BoardTask.ID>
    /// Restored from a previous launch; their completion handlers are gone.
    private var restored: Set<BoardTask.ID>

    private var onChange: (@Sendable (Set<BoardTask.ID>) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = Set(defaults.stringArray(forKey: defaultsKey) ?? [])
        self.ids = stored
        self.restored = stored
    }

    var current: Set<BoardTask.ID> { ids }

    func observe(_ handler: @escaping @Sendable (Set<BoardTask.ID>) -> Void) {
        onChange = handler
        handler(ids)
    }

    func markPending(_ taskIDs: [BoardTask.ID]) {
        guard !taskIDs.isEmpty else { return }
        ids.formUnion(taskIDs)
        persist()
    }

    func markAcknowledged(_ taskIDs: [BoardTask.ID]) {
        guard !taskIDs.isEmpty else { return }
        ids.subtract(taskIDs)
        restored.subtract(taskIDs)
        persist()
    }

    /// Drops markers from a previous launch, once a round-trip proves Firebase has
    /// replayed its queue. Writes from this session are untouched.
    func clearRestored() {
        guard !restored.isEmpty else { return }
        ids.subtract(restored)
        restored.removeAll()
        persist()
    }

    private func persist() {
        defaults.set(Array(ids), forKey: defaultsKey)
        onChange?(ids)
    }
}
