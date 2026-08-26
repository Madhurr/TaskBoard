---
tags: [taskboard, kb, gotchas]
---

# 07 Gotchas

← [[00 Index]] · prev [[06 Testing Guide]] · next [[08 Build and Run]]

## Historical bugs — do not reintroduce

### The tiebreak that never converged
`resolve` compared `local.id <= remote.id`. But it compares **two versions of the same task**, so ids are always equal → silently "always keep local" → devices never converge.
**Guard:** the symmetry test in `BoardLogicTests`. Keep it. See [[02 Invariants]] I1.

### Positions from a stale snapshot
Three quick `createTask` calls produced reversed order. Each computed its position from `snapshot.tasks`, which arrives **asynchronously** — all three saw an empty column.
**Fix:** `localOverlay`. Timestamps can't fix this; edits in one clock tick share `updatedAt`.

### Rejected write reported as failed load
Load and write failures shared one untyped `String?`, so a rejected write triggered the "Couldn't load your board" takeover while the board sat visible behind it.
**Fix:** `SyncIssue.Kind`. Keep the distinction when adding new error paths.

---

## Live traps

### Deletes are impossible via the API
The `updatedAt` rule guard blocks hard deletes (a delete has no `newData.updatedAt`). Harmless — the app only soft-deletes — but **console cleanup requires the Firebase UI**.

### `keepSynced(true)` costs bandwidth
Keeps `/tasks` warm in cache even with no listener. Fine at this scale; reconsider for a large dataset.

### Pending markers can over-report
Firebase's completion handlers don't survive process death. Markers are persisted and cleared on the first round-trip after reconnect. That heuristic **over-reports briefly, never under-reports**.

### Locked-mode database denies everything
A Realtime Database created in *locked mode* rejects all reads and writes. Publish `database.rules.json` in the console or the app shows "Couldn't reach the server".

### The dragged card must be excluded from its own drop index
`insertionIndex(for:at:)` filters out `draggedID`. `BoardLogic.move` expects an index into the destination column **without** the moved task. Include it and "drop one slot down" becomes a no-op.

### `@State` not `@StateObject`
With `@Observable`, ownership is `@State`. `@StateObject` belongs to the `ObservableObject` world and won't work.

### Xcode project is generated
`project.yml` is the source of truth. Run `xcodegen generate` after changing it. The `.xcodeproj` is committed so a clean clone opens without XcodeGen — don't hand-edit it.
