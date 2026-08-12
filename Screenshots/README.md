# Screenshots

Captured on iPhone 17 Pro (iOS 26). Filenames below are referenced from the
root README — keep them if you replace the images.

| File | What to capture |
|---|---|
| `board-dark.png` | Board mode, dark, populated — the primary view |
| `board-light.png` | Board mode, light — same data, shows the token pairs resolve |
| `list.png` | List mode, showing all three sections |
| `editor.png` | Task editor sheet, editing an existing task (shows the sync footer) |
| `empty-state.png` | First launch, empty board |
| `offline.png` | Offline with queued changes — header pill plus per-card badges |
| `undo.png` | Undo toast after a delete |
| `developer.png` | ⋯ → Developer sheet |

To capture:

```bash
xcrun simctl io booted screenshot Screenshots/board-dark.png
xcrun simctl ui booted appearance light   # or dark
```

For the offline and failure shots, use **⋯ → Developer → Use simulated backend**,
relaunch, then toggle *Force offline* or raise the failure rate.
