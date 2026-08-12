import Foundation

/// Mirrors Firebase's write queue for display purposes.
///
/// Realtime Database queues offline writes durably and replays them on reconnect,
/// but it exposes no per-record view of what is still outstanding — and the
/// assignment requires the user to be able to tell whether a change has synced.
/// This tracks which task ids have a write in flight. It never gates, retries, or
/// reorders anything; Firebase remains the only thing that actually delivers.
///
/// One honest limitation, documented in the README: Firebase fires a write's
/// completion handler only once the server acknowledges it, and those handlers do
/// not survive process death. A change made offline and then relaunched into is
/// still replayed by Firebase, but its acknowledgement never reaches us. The set is
/// therefore persisted and cleared on the first server round-trip after reconnect,
/// which is a heuristic — it can briefly over-report, and never under-reports.
actor PendingWriteTracker {

    private let defaultsKey = "pendingWriteIDs"
    private let defaults: UserDefaults

    private var ids: Set<BoardTask.ID>
    /// Ids restored from a previous launch, whose completion handlers are gone.
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

    /// Clears markers left over from a previous launch.
    ///
    /// Called once the app has been connected and has seen a server round-trip, by
    /// which point Firebase has replayed whatever it had queued. Writes issued in
    /// *this* session are untouched — those still have live completion handlers and
    /// will clear themselves properly.
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
