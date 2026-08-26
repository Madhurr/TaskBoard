---
tags: [taskboard, kb, reference]
---

# 09 Glossary

← [[00 Index]] · prev [[08 Build and Run]]

| Term | Meaning here |
|---|---|
| **Actor reentrancy** | At every `await` inside an actor, other queued work may run. State read before can be stale after. |
| **Composition root** | The single place the object graph is built — `AppEnvironment`. |
| **CRDT** | Conflict-free replicated data type. Guarantees convergence; more machinery than this needs. |
| **Existential** (`any`) | Protocol type resolved at runtime. Lets one view model hold either repository. |
| **Fake** | A working, simplified implementation. `InMemoryTaskRepository`. Contrast **stub** (canned answers) and **mock** (asserts calls). |
| **Fractional index** | Ordering by `Double`; insert = midpoint of neighbours. One write per move. |
| **Functional core / imperative shell** | Pure decisions in `BoardLogic`; effects in the shell around it. |
| **Idempotent** | Applying twice = applying once. Each write is a full object keyed by stable id. |
| **LWW** | Last-write-wins. Newest `updatedAt` wins, enforced client-side *and* in the rules. |
| **Optimistic UI** | Apply locally at once, reconcile later. |
| **Optimistic overlay** | `localOverlay` — in-flight writes shadowing the snapshot stream. |
| **Rebalance** | Renumbering a column whose fractional gaps have exhausted `Double` precision. |
| **Reentrancy re-check** | Re-validating state after an `await` inside an actor. |
| **Sendable** | Safe to cross concurrency domains. Compiler-checked. |
| **Snapshot** | `RepositorySnapshot` — tasks + sync + pendingIDs in one value so they can't tear. |
| **Tearing** | UI showing two pieces of related state from different moments. |
| **Tombstone** | A record marked `isDeleted` rather than removed. |
| **Total order** | A comparison where no two distinct items tie. Required of `isOrderedBefore` and the conflict tiebreak. |
| **Unidirectional flow** | Intents down, snapshots up. Views never mutate. |
