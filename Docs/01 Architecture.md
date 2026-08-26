---
tags: [taskboard, kb, architecture]
---

# 01 Architecture

← [[00 Index]] · next [[02 Invariants]]

## Pattern names

**MVVM + repository + functional core / imperative shell.** Data flows one way: intents down, snapshots up.

## Data flow

```
User gesture
     ↓
BoardViewModel.move() / createTask() / delete()      ← intent
     ↓
BoardLogic.move(...)                                 ← pure decision
     ↓
TaskRepository.save([BoardTask])                     ← durable locally, queued remotely
     ↓
AsyncStream<RepositorySnapshot>                      ← tasks + sync + pending, ONE value
     ↓
BoardViewModel.apply(snapshot)                       ← merged with optimistic overlay
     ↓
SwiftUI re-renders
```

Nothing writes back up the chain.

## Why the core is pure

`BoardLogic` has no dependency on Firebase, SwiftUI, or the clock. Every function is total — same inputs, same outputs. Consequences:

- The interesting half of the app tests without a simulator or network (62 tests, ~0.15s)
- Rules can be reasoned about in isolation
- Adding a rule doesn't require touching async code

**When extending: push logic *into* the core.** If you find yourself writing an `if` in a view, it probably belongs in `BoardLogic`.

## The repository seam

```swift
protocol TaskRepository: Sendable {
    func snapshots() -> AsyncStream<RepositorySnapshot>
    func start() async
    func save(_ tasks: [BoardTask]) async throws
    func clearError() async
}
```

Two implementations:

| | `FirebaseTaskRepository` | `InMemoryTaskRepository` |
|---|---|---|
| Used by | the app | tests, previews, developer sheet |
| Storage | RTDB local cache | a dictionary |
| Offline | Firebase's own queue | a modelled queue that replays |
| Extras | — | latency, failure rate, forced offline |

The view model cannot tell them apart. This buys a hermetic test suite, working previews, and the in-app developer sheet from one abstraction.

## Composition root

`AppEnvironment` is the only place the object graph is assembled — `live()` and `simulated()`. Everything below is ignorant of which backend it has. Backend choice happens **at launch**, not live, so a running board is never half-attached to both.

## The single write funnel

Every mutation goes through one private `BoardViewModel.write()`:

1. Publish an undo step (previous versions of affected tasks)
2. Apply optimistically to `localOverlay`
3. Persist via the repository
4. On failure, surface a message — **never roll the change back**

> [!important] Why no rollback
> The write is already durable locally and will be retried. Discarding it on screen would throw away work the app has in fact kept.

## The optimistic overlay

Snapshots arrive asynchronously. Between issuing a write and seeing it return, the stream still describes the old world. `localOverlay` shadows in-flight writes until the repository echoes them back.

Without it: the next edit computes its position from stale data. See [[07 Gotchas]].
