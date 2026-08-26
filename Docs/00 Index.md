---
tags: [taskboard, kb, moc]
---

# TaskBoard Knowledge Base

> [!abstract] What this is
> Engineering documentation for extending TaskBoard. Written so a person — or an AI session with no prior context — can orient in a few minutes and make a correct change.

> [!warning] Read this first
> [[02 Invariants]] — the rules that break **silently** if violated. Everything else is recoverable; these are not.

## Start here

| Doc | Read when |
|---|---|
| [[01 Architecture]] | Orienting — what the layers are and how data flows |
| [[02 Invariants]] | ⭐ **Before any change** |
| [[03 Data Model]] | Touching `BoardTask` or the wire format |
| [[04 Extension Recipes]] | Adding a feature — step-by-step recipes |
| [[05 Concurrency Rules]] | Touching a repository, actor, or async code |
| [[06 Testing Guide]] | Writing tests |
| [[07 Gotchas]] | Something behaves unexpectedly |
| [[08 Build and Run]] | Commands, XcodeGen, simulator, Firebase setup |
| [[09 Glossary]] | Unfamiliar term |

## The system in one paragraph

A three-column board (To Do / In Progress / Done) that stays fully usable offline and reconciles with Firebase Realtime Database on reconnect. Firebase's local cache **is** the durable store — persistence is enabled, so writes apply locally and queue across process death. Domain rules live in `BoardLogic` as pure functions; the view model orchestrates; views never mutate. Ordering uses fractional indices so a move is one write. Deletes are soft. Conflicts resolve last-write-wins, enforced both client-side and in the security rules.

## Layer map

```
Views/         SwiftUI. Presentation only. NEVER mutates a task.
ViewModels/    BoardViewModel — @Observable @MainActor. Orchestrates, does not decide.
Logic/         BoardLogic — PURE. All domain rules.
Repository/    TaskRepository protocol + Firebase and InMemory actors.
Models/        BoardTask, TaskStatus, SyncState, SyncSummary, SyncIssue.
```

> [!tip] Rule of thumb
> A new domain rule goes in `BoardLogic` as a pure static function, gets a unit test, and is *called* from the view model. It never goes in a view.
