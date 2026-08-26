---
tags: [taskboard, kb, build]
---

# 08 Build & Run

← [[00 Index]] · prev [[07 Gotchas]] · next [[09 Glossary]]

## Commands

```bash
# Build
xcodebuild build -project TaskBoard.xcodeproj -scheme TaskBoard \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Test  (62 tests, ~0.15s)
xcodebuild test -project TaskBoard.xcodeproj -scheme TaskBoard \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Regenerate the project after editing project.yml
xcodegen generate

# Install + launch on the booted simulator
xcrun simctl install booted <path>/TaskBoard.app
xcrun simctl launch booted com.madhurjain.taskboard

# Screenshot
xcrun simctl io booted screenshot shot.png

# Appearance
xcrun simctl ui booted appearance dark    # or light
```

## Launch arguments

```bash
xcrun simctl launch booted com.madhurjain.taskboard -debug.useSimulatedBackend YES
```

Runs against `InMemoryTaskRepository` instead of Firebase, so the developer sheet's network controls have something to act on.

## Developer sheet

In debug builds: **⋯ → Developer**

- On Firebase → offers to relaunch onto the in-memory backend
- On in-memory → *force offline*, latency slider, failure rate, outstanding-write count

These are the same controls the test suite drives.

## Firebase setup

`GoogleService-Info.plist` is committed — no configuration step. The one console action is publishing `database.rules.json` to **Realtime Database → Rules**.

> [!note] On committing the plist
> Firebase iOS API keys are **identifiers, not secrets** — they ship in every IPA. Security rules are the access control. Ours are deliberately open (no auth in the brief); root `.read: false` contains the blast radius to `/tasks`.

## Project layout

```
TaskBoard/
  App/          TaskBoardApp, AppEnvironment, FirebaseBootstrap, DebugSettings
  Models/       BoardTask, TaskStatus, SyncState
  Logic/        BoardLogic
  Repository/   TaskRepository, Firebase*, InMemory*, PendingWriteTracker, RemoteCoding
  ViewModels/   BoardViewModel, ObservationTaskBox
  Views/        BoardScreen, BoardColumnsView, TaskCardView, TaskListView,
                SyncViews, TaskEditorSheet, DebugSheet, Theme
TaskBoardTests/ BoardLogicTests, BoardViewModelTests
database.rules.json
project.yml
```
