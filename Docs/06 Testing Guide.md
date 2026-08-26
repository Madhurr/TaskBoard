---
tags: [taskboard, kb, testing, howto]
---

# 06 Testing Guide

← [[00 Index]] · prev [[05 Concurrency Rules]] · next [[07 Gotchas]]

**62 tests · 13 suites · ~0.15s · no network, no Firebase, no simulator dependency.**

```bash
xcodebuild test -project TaskBoard.xcodeproj -scheme TaskBoard \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## Framework — swift-testing

| swift-testing | XCTest |
|---|---|
| `@Test("description")` | `func testX()` |
| `@Suite("name")` | `XCTestCase` subclass |
| `#expect(x == y)` | `XCTAssertEqual` |
| `try #require(opt)` | `try XCTUnwrap` — throws, stops the test |
| `arguments: [...]` | (none) parameterised cases |
| `struct` per suite | `class` + `setUp`/`tearDown` |

`#expect` prints the **evaluated sub-expressions** on failure, so a failure is usually diagnosable from the log alone.

## Existing helpers — use these

```swift
// BoardLogicTests.swift
private func task(_ id: String, status: TaskStatus = .todo, position: Double,
                  created: TimeInterval = 0, updated: TimeInterval = 0,
                  deleted: Bool = false, title: String = "Task",
                  details: String = "") -> BoardTask

// BoardViewModelTests.swift
private final class TestClock          // controllable time
private func waitUntil(_ description: Comment, timeout:, _ condition: () -> Bool) async
private func makeBoard(tasks:conditions:) -> (BoardViewModel, InMemoryTaskRepository, TestClock)
```

## Patterns

### Pure logic — trivial

```swift
@Test("Inserting between neighbours splits the gap")
func insertBetween() {
    let column = [task("a", position: 0), task("b", position: 1024)]
    #expect(BoardLogic.position(insertingInto: column, at: 1) == 512)
}
```

### Async view model — always `waitUntil`

```swift
@Test("A new task lands at the end of its column")
func createsTask() async {
    let (board, _, clock) = makeBoard()
    await waitUntil("initial load") { board.phase == .ready }

    await board.createTask(title: "Write the README", status: .todo)
    await waitUntil("task appears") { board.columns[0].tasks.count == 1 }

    #expect(board.columns[0].tasks[0].createdAt == clock.value)
}
```

> [!warning] Never `Task.sleep` a fixed interval as synchronisation
> Mutations travel back through an `AsyncStream` and land a turn after the call returns. `waitUntil` polls with a timeout; a fixed sleep is either flaky or slow.

### Simulating a hostile network

```swift
let (board, repo, _) = makeBoard(conditions: .init(isOnline: false))
// ... or latency / failureRate
await repo.setConditions(.perfect)      // reconnect and replay
```

`InMemoryTaskRepository` is a **fake**, not a mock — it genuinely queues and replays. Its RNG is seeded (xorshift64*) so an injected failure rate repeats exactly.

## Determinism checklist

- [ ] Injected clock, never `Date()`
- [ ] Seeded RNG for any randomness
- [ ] `waitUntil`, never a bare sleep
- [ ] No network, no Firebase in the test target

> [!warning] Hosted test bundle
> Tests are hosted by the app, so `TaskBoardApp.init()` runs before them. It checks `XCTestConfigurationFilePath` and uses the simulated environment under test — otherwise the suite would hit a live database.

## What's covered

Fractional indexing · rebalancing · grouping & sorting · moving (cross-column, within-column, no-ops, tombstones) · conflict resolution (LWW, **symmetry**, deletion-wins-on-tie) · view model (create/edit/delete/undo, offline queue, failure handling)
