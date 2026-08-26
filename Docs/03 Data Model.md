---
tags: [taskboard, kb, model, architecture]
---

# 03 Data Model & Wire Format

← [[00 Index]] · prev [[02 Invariants]] · next [[04 Extension Recipes]]

## `BoardTask`

| Field | Type | Notes |
|---|---|---|
| `id` | `String` | UUID minted **on device**, so offline tasks are addressable immediately |
| `title` | `String` | Validated non-empty via `BoardLogic.isValid(title:)` |
| `details` | `String` | May be empty |
| `status` | `TaskStatus` | Which column |
| `position` | `Double` | **Fractional index**, ascending within a column |
| `createdAt` | `Date` | Never changes after creation |
| `updatedAt` | `Date` | Drives last-write-wins. Bumped on every mutation |
| `isDeleted` | `Bool` | Tombstone — see [[02 Invariants]] I7 |

## Wire format

`Repository/BoardTask+RemoteCoding.swift`. Hand-rolled, not `Codable`, because RTDB hands back `[String: Any]` full of `NSNumber`s and decoding must be **total** — one malformed record must not take the board down.

```
/tasks/{id}/
  id         String
  title      String
  details    String
  status     String     ("todo" | "inProgress" | "done")
  position   Double
  createdAt  Number     milliseconds since epoch
  updatedAt  Number     milliseconds since epoch
  isDeleted  Bool
```

**Decoding is forgiving but honest:**
- Missing `title` → returns `nil`, record is skipped (invisible beats wrong)
- Unknown `status` → falls back to `.todo` rather than vanishing
- Missing timestamps → `createdAt` falls back to `.distantPast`, `updatedAt` to `createdAt`

## Adding a field — the full checklist

> [!todo] All five steps
> 1. Add the property to `BoardTask` (+ the memberwise `init` default)
> 2. Add a `Key` constant and encode it in `remoteValue`
> 3. Decode it in `init?(remoteValue:fallbackID:)` with a safe fallback
> 4. **Add it to `conflictTiebreakKey`** if it can differ between versions ← [[02 Invariants]] I1
> 5. Update `database.rules.json` if it needs validation
>
> Then: surface it in `TaskEditorSheet` and `TaskCardView` as needed, and add a test.

## `TaskStatus`

Raw values (`"todo"`, `"inProgress"`, `"done"`) are the **wire format**. `TaskStatus.ordered` drives column layout — adding a case and appending to `ordered` is all that's needed for a new column.

Each case carries its own `title`, `symbolName`, and `accent`.

## Sync types

| Type | Role |
|---|---|
| `SyncState` | Per task: `.synced` / `.pending` / `.queuedOffline`. Synced renders **nothing** |
| `SyncSummary` | Board-wide: `isConnected` + optional `SyncIssue`. Holds **no count** — derived |
| `SyncIssue` | `.load` or `.write` + message. The kind decides how loudly the UI reports it |
| `RepositorySnapshot` | `tasks` + `sync` + `pendingIDs` in **one value** so they cannot tear |

> [!warning] Don't add a stored count
> `pendingCount` is computed from `pendingIDs`. It was stored once and the two drifted — a card said "synced" while the toolbar claimed outstanding work.
