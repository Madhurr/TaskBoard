---
tags: [taskboard, kb, concurrency, architecture]
---

# 05 Concurrency Rules

← [[00 Index]] · prev [[04 Extension Recipes]] · next [[06 Testing Guide]]

> [!warning] Swift 6 strict concurrency is ON (`SWIFT_STRICT_CONCURRENCY: complete`)
> Data-race safety is enforced as **errors**, not warnings.

## Who is isolated to what

| Type | Isolation |
|---|---|
| `BoardViewModel` | `@MainActor` |
| `FirebaseTaskRepository` | `actor` |
| `InMemoryTaskRepository` | `actor` |
| `PendingWriteTracker` | `actor` |
| `ObservationTaskBox` | `@unchecked Sendable` + `NSLock` |
| `ObserverRegistry` | `@unchecked Sendable` + `NSLock` |
| `BoardLogic` | none — pure statics, callable anywhere |
| Models | `Sendable` value types |

## Rules for new code

1. **New shared type → make it `Sendable`.** Value types of `Sendable` parts get it free.
2. **Callback-based SDK → form the closure in a `nonisolated` method** and mark it `@Sendable`. A closure written inside actor-isolated code *captures that isolation*, which the compiler rejects when you hand it to an API that calls it on its own queue.
3. **Decode non-`Sendable` SDK types before crossing into the actor.** See [[02 Invariants]] I6.
4. **`@unchecked Sendable` needs a lock and a comment.** Unjustified use reintroduces races.
5. **`deinit` cannot touch isolated state.** If a type needs cleanup, park the resource in a separate `Sendable` box whose own `deinit` does it — the `ObservationTaskBox` pattern.

## ⭐ Actor reentrancy

> [!danger]
> At every `await` inside an actor method, the actor may run **other queued work** before resuming. State read before an `await` can be stale after it.
> **Actors prevent data races; they do NOT provide atomicity across suspension points.**

Live example — `InMemoryTaskRepository.acknowledge` re-checks before clearing a marker:

```swift
// Re-check: the task may have been edited again while this was in flight.
for task in written where tasks[task.id]?.updatedAt == task.updatedAt {
    tracker.markAcknowledged([task.id])
}
```

**When you add an `await` inside an actor method, re-validate anything you read before it.**

## `AsyncStream` pattern

Repositories publish snapshots by holding continuations:

```swift
nonisolated func snapshots() -> AsyncStream<RepositorySnapshot> {
    AsyncStream { continuation in
        let id = UUID()
        Task { await self.register(continuation, id: id) }
        continuation.onTermination = { _ in Task { await self.unregister(id) } }
    }
}
```

`onTermination` is mandatory — without it a cancelled consumer leaks its continuation.

## Task lifetime

- **Structured** (`async let`, `TaskGroup`) — bounded by scope, cancellation propagates
- **Unstructured** (`Task { }`) — you own cancelling it

The view model's observation task is unstructured, which is why it lives in `ObservationTaskBox`.
