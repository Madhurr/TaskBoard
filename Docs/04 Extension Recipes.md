---
tags: [taskboard, kb, howto]
---

# 04 Extension Recipes

← [[00 Index]] · prev [[03 Data Model]] · next [[05 Concurrency Rules]]

> [!tip] Every recipe ends with a test. The suite runs in 0.15s — there is no excuse to skip it.

---

## R1 — Add a field to a task (e.g. due date)

1. **`Models/BoardTask.swift`** — add `var dueAt: Date?`, add to `init` with a default
2. **`Repository/BoardTask+RemoteCoding.swift`**
   - `Key.dueAt = "dueAt"`
   - encode: `Key.dueAt: dueAt?.millisecondsSince1970 as Any`
   - decode: `(dict[Key.dueAt] as? NSNumber)?.dateFromMilliseconds`
3. **⭐ `conflictTiebreakKey`** — append it, or [[02 Invariants]] I1 breaks
4. **`ViewModels/BoardViewModel.swift`** — thread it through `createTask` / `updateTask`
5. **`Views/TaskEditorSheet.swift`** — a `DatePicker`
6. **`Views/TaskCardView.swift`** — display it
7. **Test** — round-trip encode/decode, plus a tiebreak-symmetry case

---

## R2 — Add a fourth column

**`Models/TaskStatus.swift`** only:

```swift
case blocked                          // 1. the case
// 2. title, symbolName, accent in each switch
static let ordered: [TaskStatus] = [.todo, .inProgress, .blocked, .done]   // 3.
```

Everything else is driven off `TaskStatus.ordered`. Board columns, list sections, and the editor's picker all follow automatically.

> [!warning]
> The raw value is the wire format. Adding a case is safe; **renaming one is a migration**.

---

## R3 — Extend filtering / search

`BoardLogic.filter(_:query:statuses:)` is the single entry point. Extend its signature; `BoardViewModel.columns` is the only caller.

Matching is already case- and diacritic-insensitive via `String.matches(_:)`.

---

## R4 — Multi-step undo

Currently a single `undoStep: UndoStep?`.

1. Change to `private var undoStack: [UndoStep] = []`
2. `write()` pushes; `undo()` pops
3. Expose `var canUndo: Bool { !undoStack.isEmpty }`

`UndoStep` already holds *previous versions of affected tasks*, so the mechanism generalises without changing shape. Cap the stack (say 20) so it can't grow unbounded.

---

## R5 — Add a new domain rule

Put it in `Logic/BoardLogic.swift` as a **pure static function**:

```swift
static func archive(_ tasks: [BoardTask], olderThan cutoff: Date, now: Date) -> [BoardTask] {
    tasks.filter { $0.status == .done && $0.updatedAt < cutoff }
         .map { var c = $0; c.isDeleted = true; c.updatedAt = now; return c }
}
```

Then call it from the view model and pass the result to `write()`. **Never** put the rule in a view.

---

## R6 — Add authentication

1. Add Firebase Auth to `project.yml` dependencies, `xcodegen generate`
2. Sign in (anonymous is enough) in `FirebaseBootstrap.configure()` **before** building refs
3. Move the data root from `/tasks` to `/users/$uid/tasks`
4. Update `database.rules.json`:
   ```json
   "users": { "$uid": { ".read": "$uid === auth.uid", ".write": "$uid === auth.uid" } }
   ```
   Keep the `updatedAt` guard on the task node.
5. `FirebaseTaskRepository` takes the uid and builds its refs from it

---

## R7 — Replace the backend entirely

Conform a new type to `TaskRepository` and return it from `AppEnvironment.live()`. Nothing above the protocol changes. The four methods are `snapshots()`, `start()`, `save(_:)`, `clearError()`.

Honour [[02 Invariants]] I2 and I3: don't await the server in `save`, and keep multi-task writes atomic.

---

## R8 — Write a test

`TaskBoardTests/BoardLogicTests.swift` for pure logic, `BoardViewModelTests.swift` for behaviour.

```swift
@Test("Describes the behaviour, not the method name")
func insertBetween() {
    let column = [task("a", position: 0), task("b", position: 1024)]
    #expect(BoardLogic.position(insertingInto: column, at: 1) == 512)
}
```

For async view-model tests use the helpers already there: `makeBoard(...)`, `waitUntil(...)`, `TestClock`. See [[06 Testing Guide]].
