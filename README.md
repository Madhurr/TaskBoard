# Task Board — an offline-first task board for iOS

A three-column task board (To Do / In Progress / Done) that stays fully usable without a
network and reconciles with Firebase Realtime Database when one returns.

SwiftUI · Swift 6 (strict concurrency) · iOS 17+ · Firebase Realtime Database · 62 tests

---

## Running it

```bash
open TaskBoard.xcodeproj      # ⌘R to run, ⌘U to test
```

No configuration step. `GoogleService-Info.plist` is committed and the Firebase SDK is
resolved through Swift Package Manager, so a clean clone builds and runs.

**One thing has to be done in the Firebase console** — the database rules. A Realtime
Database created in *locked mode* denies every read and write, and the app will show
"Couldn't reach the server" against it. Paste the contents of
[`database.rules.json`](database.rules.json) into **Realtime Database → Rules → Publish**.

> The project is generated from [`project.yml`](project.yml) with
> [XcodeGen](https://github.com/yonaskolb/XcodeGen). The generated `.xcodeproj` is
> committed so the repo opens without XcodeGen installed; run `xcodegen generate` after
> changing `project.yml`.

### Seeing the offline and failure behaviour

Debug builds carry a developer sheet — **⋯ → Developer**. On Firebase it offers to
relaunch onto an in-memory backend; from there you get *force offline*, an artificial
latency slider, and an injectable failure rate. Those are the same controls the test
suite drives, so what you can reproduce by hand is exactly what the tests assert.

---

## How it is put together

```
BoardScreen ─ SwiftUI, presentation routing only
     │
BoardViewModel ─ @Observable @MainActor · owns view state, injected clock
     │
TaskRepository ─ protocol
     ├── FirebaseTaskRepository   Realtime Database + its local cache
     └── InMemoryTaskRepository   tests, previews, developer sheet
     │
BoardLogic ─ pure functions: ordering, grouping, filtering, conflict resolution
```

`BoardLogic` has no dependency on Firebase, SwiftUI, or the clock. Every rule worth
getting right lives there as a total function of its arguments, which is why the
interesting half of this app can be tested without a simulator or a network.

---

## Important technical decisions

### The local cache is the database

Firebase Realtime Database with `isPersistenceEnabled = true` is not a network client
with a cache bolted on — the cache is a real database. Reads are served from it at
launch, writes are applied to it synchronously and queued durably, and the queue
survives the process being killed. That covers the persistence requirement outright,
so there is no second store to keep in step and no class of bug where the two disagree.

`isPersistenceEnabled` must be set before any `DatabaseReference` exists or the SDK
traps at runtime, which is why it happens in `App.init()` and not a view's `.task`.

### `save` never awaits the server

`updateChildValues` applies locally at once and calls back only on acknowledgement —
which, offline, is never. Awaiting it would hang every edit made without a connection,
inverting the whole point of the app. So `save` returns as soon as the write is durable
locally, and the acknowledgement is handled out of band.

### Client-generated identifiers

Task ids are UUIDs minted on device. A task created offline is therefore complete and
addressable immediately, and edits and moves can stack up on a task the backend has
never seen.

### Ordering by fractional index

A card dropped between two others takes `position = (previous + next) / 2`, so a move
writes exactly one record. Renumbering siblings instead would mean N queued writes per
drag, which is precisely the wrong trade when those writes are offline. Repeated
subdivision does eventually exhaust `Double`, so a column whose smallest gap falls below
a threshold is renumbered — in the same atomic multi-path write as the move, so the
board is never observed mid-rebalance.

### Soft deletes

Deleting sets `isDeleted` rather than removing the node. Hard deletes race badly with
offline replay — a queued update can resurrect a removed record — and a tombstone is
what makes undo cheap.

### Conflict resolution, enforced server-side

Two devices editing the same task offline both replay on reconnect, and Realtime
Database resolves that by arrival order: the slower network wins, which is not what
anyone means by "latest". The rule in `database.rules.json`

```json
".write": "!data.exists() || newData.child('updatedAt').val() >= data.child('updatedAt').val()"
```

rejects a write carrying an older `updatedAt` than what is stored, making the outcome
depend on when the edit happened. `BoardLogic.resolve` mirrors the same policy on the
client so both sides agree.

`runTransactionBlock` would be the textbook answer and is the wrong one here: RTDB
transactions are not queued offline, so using them would break the primary requirement.

The tiebreak for two edits sharing an `updatedAt` is derived from task *content*, not
from `id` — both sides are versions of one task and share an id, so comparing ids
collapses to "always keep local" and the devices never converge. It also avoids
`hashValue`, which Swift seeds per process and which would have two devices pick
opposite winners.

### Sync status is a mirror, not a queue

Firebase queues and retries writes but exposes no per-record view of what is
outstanding, and the brief requires the user to be able to tell whether a change has
synced. `PendingWriteTracker` records which task ids have a write in flight. It never
gates, retries, or reorders anything — Firebase remains the only thing that delivers.

A synced task carries no badge at all. The absence of a mark is the signal, which keeps
a board full of unsynced work reading as a board rather than as a wall of warnings.

### Optimistic overlay in the view model

Snapshots arrive asynchronously, so between issuing a write and seeing it return there
is a window where the stream still describes the old world. Without an overlay of
in-flight writes, a snapshot emitted just before the write lands flickers the old value
back — and, worse, the next edit computes its position from stale data. Three quick taps
on *add* landed in arbitrary order until this was fixed. Timestamps cannot arbitrate it:
two edits inside one clock tick share an `updatedAt`, so last-write-wins has nothing to
compare.

### Load failures and write failures are different things

Failing to *read* the board can leave the user with nothing to look at and warrants
taking over the screen. Failing to *write* leaves everything on screen and intact and
warrants a line in the header. They were one untyped string at first, which produced
exactly the wrong pairing — a rejected write reported under "Couldn't load your board"
while the board sat visible behind the message. `SyncIssue.Kind` now separates them.

---

## Testing

62 tests, `swift-testing`, no network and no Firebase in the test target.

| Area | What is covered |
|---|---|
| Fractional indexing | insert/append/prepend, clamping, 20 rounds of subdivision staying strictly ordered |
| Rebalancing | exhausted-gap detection, minimal writes, order preservation |
| Grouping | filtering, sorting, stable tiebreak on equal positions |
| Moving | across columns, within a column, no-ops, tombstones, empty columns |
| Search & filter | case/diacritic insensitivity, composition with status filters |
| Conflict resolution | newer wins, deletions preserved, **symmetry across every field** |
| Create / edit / undo | validation, trimming, undo for delete, edit, and move |
| Offline | edits accepted, queued state surfaced, replay on reconnect |
| Failure states | rejected writes keep user work, load vs write distinction |

The clock is injected, so timestamp assertions are exact rather than "now-ish". The
in-memory repository's failure injection uses a seeded xorshift, so an injected failure
rate produces the same sequence every run.

Two of these tests exist because they caught real bugs: the conflict-resolution symmetry
test found the `id` tiebreak degeneration, and the insertion-order test found the stale
snapshot problem.

---

## Known limitations

- **Firebase reverts permanently rejected writes.** Observed live against a locked
  database: a task created while writes were denied stayed on screen with a pending
  badge, and was gone after relaunch. Because Firebase's cache is the only store, a
  hard rejection rolls the optimistic local value back and the app has no independent
  copy to defend. Offline is unaffected — writes queue and replay correctly. An explicit
  outbox with its own store would survive this; that was the trade for not maintaining
  a second database.
- **Pending markers can briefly over-report after a relaunch.** Firebase fires a write's
  completion handler only on acknowledgement and those handlers do not survive process
  death. Markers are persisted and cleared on the first server round-trip after
  reconnect, which is a heuristic — it can over-report, never under-report.
- **The database is world-readable and world-writable** within the shape the rules
  validate. There is no authentication; the brief did not ask for accounts, and adding
  them would have cost time better spent on the sync behaviour. Not suitable as-is for
  anything but a demo.
- **Cross-column moves in list mode** go through the editor rather than a drag. One
  unambiguous gesture per surface beat two competing ones.
- **Drop placement is measured from recorded card frames**, so a drop onto a column
  scrolled far off-screen falls back to appending.
- **Drag payload is a plain `String`.** A custom `Transferable` UTType would be tidier
  and would stop the columns accepting dropped text from other apps; it needs Info.plist
  declarations that did not seem worth it here.
- **No pagination.** The whole `tasks` node is observed. Fine at task-board scale,
  wrong at thousands.

---

## What I would add with more time

1. **An explicit outbox** backed by SwiftData, making the app's own store authoritative
   and closing the rejected-write gap above. This is the first thing I would do.
2. **Firebase Auth** with per-user subtrees, and rules scoped to `auth.uid`.
3. **A conflict UI** — the current policy silently picks a winner. When two devices
   genuinely disagree, showing both and asking is often better than being quietly right.
4. **Property-based tests** over sequences of random operations, asserting that any
   interleaving of offline edits converges to the same board.
5. **Snapshot tests** for the card and column states, which are currently only verified
   by eye.
6. **Background sync** via `BGTaskScheduler`. Deliberately skipped: Firebase already
   replays on foreground reconnect, so it adds entitlement complexity for very little
   user-visible gain.
7. **Accessibility passes** beyond labels — Dynamic Type at accessibility sizes will
   break the fixed 300pt columns.

---

## Assumptions

- Single user, single board, no authentication. The brief describes no accounts or
  sharing, so the data model is one flat `tasks` node.
- "Reorder" means within and across columns, with order persisted and shared — not a
  local-only view preference.
- Recency beats merging for conflicts. Task titles and descriptions are short enough
  that field-level merging would be more surprising than helpful.
- A task with an empty title is not worth persisting.
- Deletion is a normal, frequent action and should be undoable rather than confirmed
  twice — so it is a soft delete with a five-second undo, plus one confirmation from
  the editor where the action is less obviously reversible.

---

## Approximate time spent

**≈ 5 hours**, roughly: 1h architecture and the pure logic with its tests, 1h the two
repository implementations, 1.5h UI, 0.5h the design pass, 1h wiring, debugging and
verification against a live database.

---

## AI tools used

Built with **Claude Code** (Claude Opus 5), used throughout rather than for isolated
snippets. Concretely:

- **Design.** The visual system — colour tokens, card states, board and list layouts,
  empty/offline/error screens — was designed as a set of HTML specs in Claude Design
  before any SwiftUI was written, then implemented against them.
- **Implementation.** Most production and test code was written by Claude from a plan I
  reviewed and amended, in particular the fractional-indexing scheme, the actor-based
  repositories, and the Swift 6 concurrency work (Firebase's callback API needed
  `nonisolated` seams and `@Sendable` closures to satisfy strict checking).
- **Finding real bugs.** Three defects were caught by tests written alongside the code:
  the conflict tiebreak that compared `id` and so never converged, the stale-snapshot
  ordering bug, and the load-vs-write error conflation. Each fix is documented above.
- **Review.** Claude flagged the sync-status tearing that came from storing
  `pendingCount` separately from `pendingIDs`; the fix was to derive it.

My own judgement drove the architecture choice (leaning on Firebase's own offline
support rather than hand-rolling an outbox — see the trade-off in *Known limitations*),
the decision to enforce conflict resolution in security rules rather than transactions,
and what to leave out.
