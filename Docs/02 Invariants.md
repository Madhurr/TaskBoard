---
tags: [taskboard, kb, invariants, critical]
---

# 02 Invariants ⭐

← [[00 Index]] · prev [[01 Architecture]] · next [[03 Data Model]]

> [!danger] These break SILENTLY
> Violating one of these compiles fine, passes a casual manual test, and fails later in a way that is hard to trace. **Check this list before any change.**

---

## I1 — `conflictTiebreakKey` must cover every differing field

**Where:** `Models/BoardTask.swift`

```swift
var conflictTiebreakKey: String {
    [title, details, status.rawValue,
     String(position.bitPattern),
     String(createdAt.timeIntervalSince1970.bitPattern)].joined(separator: "\u{1}")
}
```

**Rule:** add a field to `BoardTask` that can differ between two versions → **add it here**.

**If violated:** two tasks differing only by the new field produce equal keys. The tiebreak stops being a total order, `resolve` becomes non-deterministic across devices, and they stop converging. There is a symmetry test that catches this — keep it passing.

**Also:** never use `hashValue` here. Swift seeds it per process; two devices would pick opposite winners.

---

## I2 — `save()` must never await the server

**Where:** `Repository/FirebaseTaskRepository.swift`

`updateChildValues` applies locally at once but calls back **only on acknowledgement** — which offline never comes.

**If violated:** every edit made without a connection hangs forever. This inverts the entire purpose of the app.

---

## I3 — Multi-task writes stay one atomic `save([...])`

A reorder that rebalances a column touches several tasks. They must go in **one** `save` call, which becomes one multi-path `updateChildValues`.

**If violated:** the write can half-apply, leaving the board in a state no user action produced — and offline, the halves can land in different sessions.

---

## I4 — `isPersistenceEnabled` before any `DatabaseReference`

**Where:** `App/AppEnvironment.swift` → `FirebaseBootstrap.configure()`, called from `App.init()`.

**If violated:** the Firebase SDK **traps at runtime**. Not a warning — a crash.

Never move this into a view's `.task` or `.onAppear`.

---

## I5 — Wire-format keys are a contract

**Where:** `Repository/BoardTask+RemoteCoding.swift` → `enum Key`

`updatedAt` is referenced by `database.rules.json`. Renaming any key is a **migration**, not a refactor — existing records in the database use the old names.

Timestamps go over the wire as **milliseconds since epoch**, matching `ServerValue.timestamp()` so the security rules can compare client and server stamps.

---

## I6 — Decode before crossing into an actor

`DataSnapshot` is **not** `Sendable`; `[BoardTask]` is. Decoding happens inside the Firebase callback so only `Sendable` values cross the isolation boundary.

**If violated:** Swift 6 strict concurrency rejects it at compile time. (This one fails loudly — listed for completeness.)

---

## I7 — Soft deletes only

Never remove a node. Set `isDeleted = true`.

**Why:** a hard delete races with offline replay — a queued update can resurrect a removed record. Also, the `updatedAt` rule guard **blocks hard deletes anyway** (a delete has no `newData.updatedAt`, so the comparison fails).

---

## I8 — The clock is injected

Logic and the view model take `now: @Sendable () -> Date`. Never call `Date()` inside `BoardLogic` or `BoardViewModel`.

**If violated:** tests become non-deterministic and timestamp assertions turn into "now-ish" comparisons.

---

## I9 — Views never mutate a task

The only two-way bindings are `searchQuery` and `statusFilter` — pure UI state that never reaches the backend.

**If violated:** you reintroduce races between what the user typed and what the server pushed, with no place to arbitrate.

---

## I10 — `undoStep` holds *previous* versions

`UndoStep.previous: [BoardTask]` — the state to write back. This is why one mechanism covers deletes, edits, and moves alike. Undo restores with a **fresh timestamp** so it wins last-write-wins against the change it reverts.
