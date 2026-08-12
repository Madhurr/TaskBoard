import Foundation
import Testing
@testable import TaskBoard

// MARK: - Helpers

/// Controllable clock, so timestamp assertions are exact.
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        current = start
    }

    var now: @Sendable () -> Date {
        { [self] in
            lock.lock()
            defer { lock.unlock() }
            return current
        }
    }

    func advance(_ interval: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        current = current.addingTimeInterval(interval)
    }

    var value: Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }
}

/// Waits for the view model to observe a snapshot. Mutations travel back through
/// an `AsyncStream`, so state lands a turn after the call returns.
@MainActor
private func waitUntil(
    _ description: Comment,
    timeout: Duration = .seconds(2),
    _ condition: () -> Bool
) async {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(1))
    }
    Issue.record("Timed out waiting for: \(description)")
}

@MainActor
private func makeBoard(
    tasks: [BoardTask] = [],
    conditions: InMemoryTaskRepository.Conditions = .perfect
) -> (BoardViewModel, InMemoryTaskRepository, TestClock) {
    let repository = InMemoryTaskRepository(tasks: tasks, conditions: conditions)
    let clock = TestClock()
    let viewModel = BoardViewModel(repository: repository, now: clock.now)
    viewModel.start()
    return (viewModel, repository, clock)
}

// MARK: - Creating

@Suite("Creating tasks")
@MainActor
struct CreateTests {

    @Test("A new task lands at the end of its column and is visible immediately")
    func createsTask() async {
        let (board, _, clock) = makeBoard()
        await waitUntil("initial load") { board.phase == .ready }

        await board.createTask(title: "Write the README", status: .todo)
        await waitUntil("task appears") { board.columns[0].tasks.count == 1 }

        let created = board.columns[0].tasks[0]
        #expect(created.title == "Write the README")
        #expect(created.status == .todo)
        #expect(created.createdAt == clock.value)
        #expect(created.updatedAt == clock.value)
        #expect(created.isDeleted == false)
    }

    @Test("Successive tasks keep insertion order")
    func appendsInOrder() async {
        let (board, _, _) = makeBoard()
        for title in ["first", "second", "third"] {
            await board.createTask(title: title)
        }
        await waitUntil("all three appear") { board.columns[0].tasks.count == 3 }

        #expect(board.columns[0].tasks.map(\.title) == ["first", "second", "third"])
    }

    @Test("Blank titles are rejected without touching the board", arguments: ["", "   ", "\n"])
    func rejectsBlankTitles(title: String) async {
        let (board, repository, _) = makeBoard()
        let created = await board.createTask(title: title)

        #expect(created == nil)
        #expect(await repository.storedTasks.isEmpty)
    }

    @Test("Titles are trimmed before they are stored")
    func trimsTitle() async {
        let (board, _, _) = makeBoard()
        await board.createTask(title: "  padded  ")
        await waitUntil("task appears") { board.columns[0].tasks.count == 1 }

        #expect(board.columns[0].tasks[0].title == "padded")
    }
}

// MARK: - Editing, deleting, undo

@Suite("Editing and undo")
@MainActor
struct MutationTests {

    @Test("Editing updates the task and stamps a new updatedAt")
    func edits() async throws {
        let (board, _, clock) = makeBoard()
        let task = try #require(await board.createTask(title: "Draft"))
        await waitUntil("created") { board.task(task.id) != nil }

        clock.advance(60)
        await board.updateTask(task.id, title: "Final", details: "with notes")
        await waitUntil("edited") { board.task(task.id)?.title == "Final" }

        let edited = try #require(board.task(task.id))
        #expect(edited.details == "with notes")
        #expect(edited.updatedAt == clock.value)
        #expect(edited.createdAt == task.createdAt, "creation date must not move")
    }

    @Test("Deleting hides the task but keeps a tombstone for sync")
    func deletes() async throws {
        let (board, repository, _) = makeBoard()
        let task = try #require(await board.createTask(title: "Temporary"))
        await waitUntil("created") { board.columns[0].tasks.count == 1 }

        await board.delete(task.id)
        await waitUntil("hidden") { board.columns[0].tasks.isEmpty }

        let stored = await repository.storedTasks
        #expect(stored.count == 1, "the record survives so the deletion can propagate")
        #expect(stored[0].isDeleted)
    }

    @Test("Undo restores a deleted task")
    func undoDelete() async throws {
        let (board, _, clock) = makeBoard()
        let task = try #require(await board.createTask(title: "Important"))
        await waitUntil("created") { board.columns[0].tasks.count == 1 }

        clock.advance(30)
        await board.delete(task.id)
        await waitUntil("hidden") { board.columns[0].tasks.isEmpty }
        #expect(board.undoStep?.label == "Task restored")

        clock.advance(30)
        await board.undo()
        await waitUntil("restored") { board.columns[0].tasks.count == 1 }

        #expect(board.columns[0].tasks[0].title == "Important")
        #expect(board.undoStep == nil, "the step is consumed")
    }

    @Test("Undo restores the previous text of an edit")
    func undoEdit() async throws {
        let (board, _, clock) = makeBoard()
        let task = try #require(await board.createTask(title: "Original", details: "first"))
        await waitUntil("created") { board.task(task.id) != nil }

        clock.advance(10)
        await board.updateTask(task.id, title: "Changed", details: "second")
        await waitUntil("edited") { board.task(task.id)?.title == "Changed" }

        clock.advance(10)
        await board.undo()
        await waitUntil("reverted") { board.task(task.id)?.title == "Original" }

        #expect(board.task(task.id)?.details == "first")
    }

    @Test("An undone change is stamped later than the change it reverts, so it wins")
    func undoWinsLastWriteWins() async throws {
        let (board, _, clock) = makeBoard()
        let task = try #require(await board.createTask(title: "Original"))
        await waitUntil("created") { board.task(task.id) != nil }

        clock.advance(10)
        await board.updateTask(task.id, title: "Changed", details: "")
        await waitUntil("edited") { board.task(task.id)?.title == "Changed" }
        let editedAt = try #require(board.task(task.id)).updatedAt

        clock.advance(10)
        await board.undo()
        await waitUntil("reverted") { board.task(task.id)?.title == "Original" }

        #expect(try #require(board.task(task.id)).updatedAt > editedAt)
    }

    @Test("Undo with nothing recorded is a no-op")
    func undoWithoutStep() async {
        let (board, repository, _) = makeBoard()
        await board.undo()
        #expect(await repository.storedTasks.isEmpty)
    }

    @Test("Editing a task that does not exist is ignored")
    func editsUnknownTask() async {
        let (board, repository, _) = makeBoard()
        await board.updateTask("ghost", title: "Nope", details: "")
        #expect(await repository.storedTasks.isEmpty)
    }
}

// MARK: - Moving

@Suite("Moving and reordering")
@MainActor
struct BoardMoveTests {

    @Test("Moving across columns changes status and lands at the requested slot")
    func movesAcrossColumns() async throws {
        let (board, _, _) = makeBoard()
        let a = try #require(await board.createTask(title: "A", status: .todo))
        await board.createTask(title: "X", status: .inProgress)
        await board.createTask(title: "Y", status: .inProgress)
        await waitUntil("seeded") { board.columns[1].tasks.count == 2 }

        await board.move(a.id, to: .inProgress, targetIndex: 1)
        await waitUntil("moved") { board.columns[1].tasks.count == 3 }

        #expect(board.columns[1].tasks.map(\.title) == ["X", "A", "Y"])
        #expect(board.columns[0].tasks.isEmpty)
    }

    @Test("Reordering within a column puts the task at the requested slot")
    func reordersWithinColumn() async throws {
        let (board, _, _) = makeBoard()
        for title in ["A", "B", "C"] {
            await board.createTask(title: title)
        }
        await waitUntil("seeded") { board.columns[0].tasks.count == 3 }
        let a = try #require(board.columns[0].tasks.first { $0.title == "A" })

        await board.move(a.id, to: .todo, targetIndex: 2)
        await waitUntil("reordered") { board.columns[0].tasks.last?.title == "A" }

        #expect(board.columns[0].tasks.map(\.title) == ["B", "C", "A"])
    }

    @Test("Undo returns a moved task to its original column and slot")
    func undoMove() async throws {
        let (board, _, clock) = makeBoard()
        let a = try #require(await board.createTask(title: "A", status: .todo))
        await waitUntil("seeded") { board.columns[0].tasks.count == 1 }

        clock.advance(10)
        await board.move(a.id, to: .done, targetIndex: 0)
        await waitUntil("moved") { board.columns[2].tasks.count == 1 }

        clock.advance(10)
        await board.undo()
        await waitUntil("returned") { board.columns[0].tasks.count == 1 }

        #expect(board.columns[2].tasks.isEmpty)
        #expect(board.columns[0].tasks[0].position == a.position)
    }

    @Test("A move that changes nothing does not record an undo step")
    func noOpMove() async throws {
        let (board, _, _) = makeBoard()
        let a = try #require(await board.createTask(title: "A"))
        await waitUntil("seeded") { board.columns[0].tasks.count == 1 }
        board.dismissUndo()

        await board.move(a.id, to: .todo, targetIndex: 0)
        #expect(board.undoStep == nil)
    }

    @Test("A column whose positions are exhausted is renumbered on the next move")
    func rebalances() async throws {
        // Packed closer than the minimum gap, forcing a rebalance.
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let packed = [
            BoardTask(id: "a", title: "A", status: .todo, position: 0, createdAt: base, updatedAt: base),
            BoardTask(id: "b", title: "B", status: .todo, position: 0.000_000_1, createdAt: base, updatedAt: base),
            BoardTask(id: "c", title: "C", status: .todo, position: 5, createdAt: base, updatedAt: base),
        ]
        let (board, _, _) = makeBoard(tasks: packed)
        await waitUntil("seeded") { board.columns[0].tasks.count == 3 }

        await board.move("c", to: .todo, targetIndex: 0)
        await waitUntil("moved") { board.columns[0].tasks.first?.id == "c" }

        let column = board.columns[0]
        #expect(column.tasks.map(\.id) == ["c", "a", "b"])
        #expect(BoardLogic.needsRebalance(column.tasks) == false, "gaps must be healthy again")
    }
}

// MARK: - Offline behaviour

@Suite("Offline behaviour")
@MainActor
struct OfflineTests {

    @Test("Every kind of edit is accepted while offline")
    func acceptsEditsOffline() async throws {
        let (board, repository, _) = makeBoard(conditions: .offline)
        await waitUntil("ready") { board.phase == .ready }

        let a = try #require(await board.createTask(title: "Offline task"))
        await waitUntil("created") { board.columns[0].tasks.count == 1 }

        await board.updateTask(a.id, title: "Renamed offline", details: "notes")
        await board.move(a.id, to: .inProgress, targetIndex: 0)
        await waitUntil("moved") { board.columns[1].tasks.count == 1 }

        #expect(board.columns[1].tasks[0].title == "Renamed offline")
        #expect(await repository.storedTasks.count == 1)
        #expect(board.writeError == nil, "working offline is not an error")
    }

    @Test("Offline edits are surfaced as waiting for a connection")
    func reportsQueuedState() async throws {
        let (board, _, _) = makeBoard(conditions: .offline)
        let a = try #require(await board.createTask(title: "Queued"))
        await waitUntil("created") { board.columns[0].tasks.count == 1 }

        #expect(board.syncState(for: board.columns[0].tasks[0]) == .queuedOffline)
        #expect(board.snapshot.sync.isConnected == false)
        #expect(board.snapshot.pendingCount == 1)
        #expect(board.snapshot.pendingIDs.contains(a.id))
    }

    @Test("Reconnecting drains the queue and clears the pending markers")
    func replaysOnReconnect() async throws {
        let (board, repository, _) = makeBoard(conditions: .offline)
        await board.createTask(title: "One")
        await board.createTask(title: "Two")
        await waitUntil("queued") { board.snapshot.pendingCount == 2 }

        await repository.setConditions(.perfect)
        await waitUntil("drained") { board.snapshot.pendingCount == 0 }

        #expect(board.snapshot.sync.isConnected)
        #expect(board.columns[0].tasks.count == 2)
        for task in board.columns[0].tasks {
            #expect(board.syncState(for: task) == .synced)
        }
    }

    @Test("A task synced normally carries no pending badge")
    func syncedTasksAreQuiet() async throws {
        let (board, _, _) = makeBoard()
        await board.createTask(title: "Online")
        await waitUntil("synced") { board.snapshot.pendingCount == 0 && board.columns[0].tasks.count == 1 }

        #expect(board.syncState(for: board.columns[0].tasks[0]) == .synced)
        #expect(board.snapshot.isQuiet)
    }
}

// MARK: - Failure states

@Suite("Failure states")
@MainActor
struct FailureTests {

    @Test("A rejected write reports the failure but keeps the user's work")
    func keepsWorkOnWriteFailure() async throws {
        let (board, repository, _) = makeBoard(
            conditions: .init(isOnline: true, failureRate: 1.0)
        )
        await waitUntil("ready") { board.phase == .ready }

        await board.createTask(title: "Precious")
        await waitUntil("error surfaced") { board.writeError != nil }

        // A failed sync must not discard the edit.
        #expect(board.columns[0].tasks.count == 1)
        #expect(board.columns[0].tasks[0].title == "Precious")
        #expect(await repository.storedTasks.count == 1)
        #expect(board.snapshot.pendingIDs.count == 1, "still marked unsynced")
    }

    /// Regression: load and write failures shared one untyped string, so a rejected
    /// write rendered under the "Couldn't load your board" takeover.
    @Test("A rejected write is reported in the header, not as a failed board")
    func writeFailureDoesNotTakeOverTheScreen() async throws {
        let (board, _, _) = makeBoard(conditions: .init(isOnline: true, failureRate: 1.0))
        await waitUntil("ready") { board.phase == .ready }

        await board.createTask(title: "Precious")
        // `writeError` is set by the throw first; wait for the typed issue.
        await waitUntil("error surfaced") { board.snapshot.sync.lastError != nil }

        #expect(board.phase == .ready, "the board still has content and must stay visible")
        #expect(board.snapshot.sync.lastError?.kind == .write)
    }

    @Test("A failed load with an empty board does take over the screen")
    func loadFailureTakesOverTheScreen() async {
        let (board, _, _) = makeBoard(conditions: .init(loadError: .loadFailed("Network unreachable.")))
        await waitUntil("failure surfaced") { board.phase != .loading }

        #expect(board.snapshot.sync.lastError?.kind == .load)
        guard case .failed = board.phase else {
            Issue.record("expected a failed phase, got \(board.phase)")
            return
        }
    }

    @Test("Dismissing an error clears it from both the board and the repository")
    func dismissesError() async throws {
        let (board, _, _) = makeBoard(conditions: .init(isOnline: true, failureRate: 1.0))
        await board.createTask(title: "Fails")
        await waitUntil("error surfaced") { board.writeError != nil }

        await board.dismissError()
        await waitUntil("cleared") { board.snapshot.sync.lastError == nil }
        #expect(board.writeError == nil)
    }

    @Test("A failed initial load with no cached data is reported as a failure")
    func reportsLoadFailure() async {
        let (board, _, _) = makeBoard(
            conditions: .init(loadError: .loadFailed("Network unreachable."))
        )
        await waitUntil("failure surfaced") { board.phase != .loading }

        guard case .failed(let message) = board.phase else {
            Issue.record("expected a failed phase, got \(board.phase)")
            return
        }
        #expect(message.contains("Network unreachable"))
    }

    @Test("A failed load still shows cached tasks rather than an error screen")
    func prefersCacheOverError() async {
        let cached = [
            BoardTask(
                id: "cached", title: "From disk", status: .todo, position: 0,
                createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 1)
            )
        ]
        let (board, _, _) = makeBoard(
            tasks: cached,
            conditions: .init(loadError: .loadFailed("Network unreachable."))
        )
        await waitUntil("ready") { board.phase == .ready }

        #expect(board.columns[0].tasks.map(\.title) == ["From disk"])
    }
}

// MARK: - Search and filtering

@Suite("Search and filtering")
@MainActor
struct SearchTests {

    @MainActor
    private func seeded() async -> BoardViewModel {
        let (board, _, _) = makeBoard()
        await board.createTask(title: "Ship release", details: "cut the build", status: .todo)
        await board.createTask(title: "Review PR", details: "ship it", status: .inProgress)
        await board.createTask(title: "Archive notes", status: .done)
        await waitUntil("seeded") { board.snapshot.tasks.count == 3 }
        return board
    }

    @Test("Searching narrows every column at once")
    func searches() async {
        let board = await seeded()
        board.searchQuery = "ship"

        #expect(board.columns[0].tasks.map(\.title) == ["Ship release"])
        #expect(board.columns[1].tasks.map(\.title) == ["Review PR"])
        #expect(board.columns[2].tasks.isEmpty)
        #expect(board.isFiltering)
    }

    @Test("A status filter restricts results and composes with search")
    func filtersByStatus() async {
        let board = await seeded()
        board.toggleFilter(.done)

        #expect(board.columns[0].tasks.isEmpty)
        #expect(board.columns[2].tasks.map(\.title) == ["Archive notes"])

        board.searchQuery = "ship"
        #expect(board.columns[2].tasks.isEmpty)
        #expect(board.hasNoMatches)
    }

    @Test("Clearing filters restores the full board")
    func clearsFilters() async {
        let board = await seeded()
        board.searchQuery = "nothing matches this"
        board.toggleFilter(.todo)
        #expect(board.hasNoMatches)

        board.clearFilters()
        #expect(board.isFiltering == false)
        #expect(board.columns.flatMap(\.tasks).count == 3)
    }

    @Test("An empty board is distinguished from a filter that hid everything")
    func distinguishesEmptyFromFiltered() async {
        let (empty, _, _) = makeBoard()
        await waitUntil("ready") { empty.phase == .ready }
        #expect(empty.isBoardEmpty)
        #expect(empty.hasNoMatches == false)

        let board = await seeded()
        board.searchQuery = "zzzz"
        #expect(board.isBoardEmpty == false)
        #expect(board.hasNoMatches)
    }
}
