import Foundation
import Testing
@testable import TaskBoard

// MARK: - Fixtures

private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

private func task(
    _ id: String,
    status: TaskStatus = .todo,
    position: Double,
    created: TimeInterval = 0,
    updated: TimeInterval = 0,
    deleted: Bool = false,
    title: String = "Task",
    details: String = ""
) -> BoardTask {
    BoardTask(
        id: id,
        title: title,
        details: details,
        status: status,
        position: position,
        createdAt: epoch.addingTimeInterval(created),
        updatedAt: epoch.addingTimeInterval(updated),
        isDeleted: deleted
    )
}

// MARK: - Fractional indexing

@Suite("Fractional indexing")
struct PositionTests {

    @Test("First task in an empty column anchors at zero")
    func emptyColumn() {
        #expect(BoardLogic.position(insertingInto: [], at: 0) == 0)
    }

    @Test("Appending leaves a full step of headroom")
    func append() {
        let column = [task("a", position: 0), task("b", position: 1024)]
        #expect(BoardLogic.position(insertingInto: column, at: 2) == 1024 + BoardLogic.positionStep)
    }

    @Test("Prepending walks below the first item rather than halving toward zero")
    func prepend() {
        let column = [task("a", position: 0)]
        #expect(BoardLogic.position(insertingInto: column, at: 0) == -BoardLogic.positionStep)
    }

    @Test("Inserting between neighbours splits the gap")
    func insertBetween() {
        let column = [task("a", position: 0), task("b", position: 1024)]
        #expect(BoardLogic.position(insertingInto: column, at: 1) == 512)
    }

    @Test("Out-of-range indices clamp instead of trapping")
    func clamping() {
        let column = [task("a", position: 0), task("b", position: 1024)]
        #expect(BoardLogic.position(insertingInto: column, at: -5) == -BoardLogic.positionStep)
        #expect(BoardLogic.position(insertingInto: column, at: 99) == 1024 + BoardLogic.positionStep)
    }

    @Test("Repeatedly inserting into the same gap keeps strict ordering")
    func repeatedSubdivision() {
        var column = [task("a", position: 0), task("z", position: 1024)]
        for i in 0..<20 {
            let p = BoardLogic.position(insertingInto: column, at: 1)
            column.insert(task("t\(i)", position: p), at: 1)
        }
        let positions = column.map(\.position)
        #expect(positions == positions.sorted())
        #expect(Set(positions).count == positions.count, "positions must stay distinct")
    }
}

@Suite("Rebalancing")
struct RebalanceTests {

    @Test("A healthy column needs no rebalance")
    func healthy() {
        let column = [task("a", position: 0), task("b", position: 1024)]
        #expect(BoardLogic.needsRebalance(column) == false)
    }

    @Test("A single item never needs rebalance")
    func single() {
        #expect(BoardLogic.needsRebalance([task("a", position: 3)]) == false)
        #expect(BoardLogic.needsRebalance([]) == false)
    }

    @Test("An exhausted gap is detected")
    func exhausted() {
        let column = [task("a", position: 0), task("b", position: 0.000_001)]
        #expect(BoardLogic.needsRebalance(column))
    }

    @Test("Rebalancing renumbers on the step and preserves order")
    func renumbers() {
        let column = [task("a", position: 0), task("b", position: 0.000_001), task("c", position: 5)]
        let changed = BoardLogic.rebalanced(column)
        let byID = Dictionary(uniqueKeysWithValues: changed.map { ($0.id, $0.position) })

        #expect(byID["b"] == BoardLogic.positionStep)
        #expect(byID["c"] == BoardLogic.positionStep * 2)
        #expect(byID["a"] == nil, "already correct, so not rewritten")
    }

    @Test("Rebalancing only returns records that actually changed")
    func minimalWrites() {
        let column = [task("a", position: 0), task("b", position: 1024), task("c", position: 2048)]
        #expect(BoardLogic.rebalanced(column).isEmpty)
    }
}

// MARK: - Grouping

@Suite("Grouping")
struct ColumnTests {

    @Test("A column contains only live tasks of that status, in position order")
    func filtersAndSorts() {
        let tasks = [
            task("c", status: .todo, position: 30),
            task("a", status: .todo, position: 10),
            task("gone", status: .todo, position: 20, deleted: true),
            task("other", status: .done, position: 5),
            task("b", status: .todo, position: 20),
        ]
        #expect(BoardLogic.column(.todo, in: tasks).map(\.id) == ["a", "b", "c"])
    }

    @Test("Equal positions fall back to creation date, then id")
    func stableTiebreak() {
        let tasks = [
            task("z", position: 10, created: 5),
            task("a", position: 10, created: 5),
            task("early", position: 10, created: 1),
        ]
        #expect(BoardLogic.column(.todo, in: tasks).map(\.id) == ["early", "a", "z"])
    }

    @Test("All three columns are produced in display order")
    func allColumns() {
        let result = BoardLogic.columns(in: [task("a", status: .done, position: 0)])
        #expect(result.map(\.status) == [.todo, .inProgress, .done])
        #expect(result[2].tasks.map(\.id) == ["a"])
        #expect(result[0].tasks.isEmpty)
    }
}

// MARK: - Moving

@Suite("Moving")
struct MoveTests {

    private let board = [
        task("a", status: .todo, position: 0),
        task("b", status: .todo, position: 1024),
        task("c", status: .todo, position: 2048),
        task("x", status: .inProgress, position: 0),
        task("y", status: .inProgress, position: 1024),
    ]

    @Test("Moving across columns adopts the new status and a slot position")
    func acrossColumns() throws {
        let moved = try #require(
            BoardLogic.move(taskID: "a", to: .inProgress, targetIndex: 1, in: board, now: epoch)
        )
        #expect(moved.status == .inProgress)
        #expect(moved.position == 512)
    }

    @Test("Moving within a column excludes the task from its own destination gap")
    func withinColumn() throws {
        // Dragging "a" to the end of To Do must land after "c", not after itself.
        let moved = try #require(
            BoardLogic.move(taskID: "a", to: .todo, targetIndex: 2, in: board, now: epoch)
        )
        #expect(moved.position == 2048 + BoardLogic.positionStep)

        var applied = board.filter { $0.id != "a" }
        applied.append(moved)
        #expect(BoardLogic.column(.todo, in: applied).map(\.id) == ["b", "c", "a"])
    }

    @Test("A move that changes nothing is reported as a no-op")
    func noOp() {
        #expect(BoardLogic.move(taskID: "b", to: .todo, targetIndex: 1, in: board, now: epoch) == nil)
    }

    @Test("Moving stamps updatedAt")
    func stampsTimestamp() throws {
        let later = epoch.addingTimeInterval(500)
        let moved = try #require(
            BoardLogic.move(taskID: "a", to: .done, targetIndex: 0, in: board, now: later)
        )
        #expect(moved.updatedAt == later)
    }

    @Test("Unknown and deleted tasks cannot be moved")
    func rejectsInvalid() {
        #expect(BoardLogic.move(taskID: "nope", to: .done, targetIndex: 0, in: board, now: epoch) == nil)

        let withTombstone = board + [task("dead", position: 99, deleted: true)]
        #expect(BoardLogic.move(taskID: "dead", to: .done, targetIndex: 0, in: withTombstone, now: epoch) == nil)
    }

    @Test("Moving into an empty column succeeds")
    func intoEmptyColumn() throws {
        let moved = try #require(
            BoardLogic.move(taskID: "a", to: .done, targetIndex: 0, in: board, now: epoch)
        )
        #expect(moved.status == .done)
        #expect(moved.position == 0)
    }
}

// MARK: - Search & filter

@Suite("Search and filter")
struct FilterTests {

    private let tasks = [
        task("a", status: .todo, position: 0, title: "Ship the résumé"),
        task("b", status: .done, position: 0, title: "Review PR", details: "check the RESUME flow"),
        task("c", status: .todo, position: 1, deleted: true, title: "Resume subscription"),
    ]

    @Test("An empty query returns every live task")
    func emptyQuery() {
        #expect(BoardLogic.filter(tasks, query: "   ", statuses: []).map(\.id) == ["a", "b"])
    }

    @Test("Matching ignores case and diacritics, and searches details")
    func fuzzyMatch() {
        #expect(BoardLogic.filter(tasks, query: "resume", statuses: []).map(\.id) == ["a", "b"])
    }

    @Test("Deleted tasks never surface in results")
    func excludesDeleted() {
        #expect(BoardLogic.filter(tasks, query: "Resume subscription", statuses: []).isEmpty)
    }

    @Test("Status filter narrows results and composes with the query")
    func statusFilter() {
        #expect(BoardLogic.filter(tasks, query: "", statuses: [.done]).map(\.id) == ["b"])
        #expect(BoardLogic.filter(tasks, query: "resume", statuses: [.done]).map(\.id) == ["b"])
        #expect(BoardLogic.filter(tasks, query: "resume", statuses: [.inProgress]).isEmpty)
    }
}

// MARK: - Conflict resolution

@Suite("Conflict resolution")
struct ResolveTests {

    @Test("The newer updatedAt wins regardless of which side it came from")
    func newerWins() {
        let older = task("t", position: 0, updated: 10, title: "old")
        let newer = task("t", position: 0, updated: 20, title: "new")

        #expect(BoardLogic.resolve(local: newer, remote: older).title == "new")
        #expect(BoardLogic.resolve(local: older, remote: newer).title == "new")
    }

    @Test("At an identical instant a deletion is preserved")
    func deletionWinsTies() {
        let alive = task("t", position: 0, updated: 10)
        let tombstone = task("t", position: 0, updated: 10, deleted: true)

        #expect(BoardLogic.resolve(local: alive, remote: tombstone).isDeleted)
        #expect(BoardLogic.resolve(local: tombstone, remote: alive).isDeleted)
    }

    @Test("Resolution is symmetric, so both devices converge")
    func symmetric() {
        let a = task("t", position: 0, updated: 10, title: "A")
        let b = task("t", position: 5, updated: 10, title: "B")

        #expect(BoardLogic.resolve(local: a, remote: b) == BoardLogic.resolve(local: b, remote: a))
    }

    /// Regression: the tiebreak once compared `id`, which is equal by construction
    /// here, so it silently degenerated into "always keep local" and two devices
    /// would each hold their own version indefinitely.
    @Test("Symmetry holds across every field that can still differ at a tie", arguments: [
        ("title", task("t", position: 0, updated: 10, title: "Z")),
        ("details", task("t", position: 0, updated: 10, details: "notes")),
        ("status", task("t", status: .done, position: 0, updated: 10)),
        ("position", task("t", position: 999, updated: 10)),
        ("createdAt", task("t", position: 0, created: 7, updated: 10)),
    ])
    func symmetricAcrossFields(field: String, variant: BoardTask) {
        let base = task("t", position: 0, updated: 10)

        let forward = BoardLogic.resolve(local: base, remote: variant)
        let backward = BoardLogic.resolve(local: variant, remote: base)

        #expect(forward == backward, "resolve must not depend on argument order (\(field))")
    }

    @Test("A task tied with an identical copy resolves to that same value")
    func idempotent() {
        let t = task("t", position: 3, updated: 10, title: "same")
        #expect(BoardLogic.resolve(local: t, remote: t) == t)
    }

    @Test("Merging unions both sides and resolves the overlap")
    func mergeSnapshots() {
        let local = [
            task("shared", position: 0, updated: 50, title: "local edit"),
            task("localOnly", position: 1),
        ]
        let remote = [
            task("shared", position: 0, updated: 10, title: "remote edit"),
            task("remoteOnly", position: 2),
        ]

        let merged = BoardLogic.merge(local: local, remote: remote)
        #expect(Set(merged.map(\.id)) == ["shared", "localOnly", "remoteOnly"])
        #expect(merged.first { $0.id == "shared" }?.title == "local edit")
    }

    @Test("An empty side leaves the other untouched")
    func mergeIdentity() {
        let local = [task("a", position: 0), task("b", position: 1)]
        #expect(BoardLogic.merge(local: local, remote: []) == local)
        #expect(BoardLogic.merge(local: [], remote: local) == local)
    }
}

// MARK: - Validation

@Suite("Validation")
struct ValidationTests {

    @Test("Titles must carry at least one non-whitespace character", arguments: [
        ("Real task", true),
        ("  padded  ", true),
        ("", false),
        ("   ", false),
        ("\n\t ", false),
    ])
    func titleValidation(input: String, expected: Bool) {
        #expect(BoardLogic.isValid(title: input) == expected)
    }
}
