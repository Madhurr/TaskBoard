# TaskBoard — project context

Offline-first task board. SwiftUI · Swift 6 strict concurrency · iOS 17+ · Firebase Realtime Database.

**Full engineering docs live in [`Docs/`](Docs/). Read `Docs/02 Invariants.md` before changing anything.**

## Build & test

```bash
xcodebuild test -project TaskBoard.xcodeproj -scheme TaskBoard \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

62 tests, ~0.15s. No network or Firebase in the test target. The project is generated
from `project.yml` via XcodeGen — run `xcodegen generate` after editing it, but the
`.xcodeproj` is committed so a clean clone opens without XcodeGen installed.

## Layer map — where a change belongs

```
Views/         SwiftUI. Presentation only. NEVER mutates a task.
ViewModels/    BoardViewModel — @Observable @MainActor. Orchestrates, does not decide.
Logic/         BoardLogic — PURE functions. All domain rules live here.
Repository/    TaskRepository protocol + Firebase and InMemory actors.
Models/        BoardTask, TaskStatus, SyncState, SyncSummary, SyncIssue.
```

**Rule of thumb:** a new domain rule goes in `Logic/BoardLogic.swift` as a pure static
function, gets a unit test, and is *called* from the view model. It does not go in a view.

## The five invariants that break silently

1. **`conflictTiebreakKey` must include every field that can differ.** Add a field to
   `BoardTask` → add it here, or the conflict tiebreak stops being a total order and
   two devices stop converging.
2. **`save()` must never await the server.** Offline the acknowledgement never comes.
3. **Multi-task writes must stay one atomic `save([...])` call.** A reorder that
   half-applies leaves the board inconsistent.
4. **`isPersistenceEnabled` must be set before any `DatabaseReference` exists** —
   `App.init()`, never a view's `.task`. Otherwise the SDK traps at runtime.
5. **Wire-format keys in `BoardTask+RemoteCoding` are a contract.** `updatedAt` is
   referenced by `database.rules.json`. Renaming is a migration, not a refactor.

## Conventions

- Swift 6 strict concurrency is **on**. New shared types need `Sendable`.
- Comments are short. Rationale belongs in `Docs/`, not in the source.
- Tests use `swift-testing` (`@Test`, `#expect`, `#require`), not XCTest.
- The clock is injected (`now: @Sendable () -> Date`). Never call `Date()` in logic.
- Soft deletes only (`isDeleted`). Never remove a node — the rules block it anyway.

## Common tasks

See `Docs/04 Extension Recipes.md` for step-by-step recipes (add a field, add a column,
extend filtering, multi-step undo, write a test).
