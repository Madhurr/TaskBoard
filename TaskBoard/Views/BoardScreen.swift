import SwiftUI

/// Root screen. Owns presentation routing only — every rule lives in the view model.
struct BoardScreen: View {

    @Bindable var board: BoardViewModel
    var simulator: InMemoryTaskRepository?

    enum Layout: String, CaseIterable { case board = "Board", list = "List" }

    @State private var layout: Layout = .board
    @State private var editor: TaskEditorSheet.Mode?
    @State private var isSearching = false
    @State private var isShowingDebug = false
    @State private var undoDismissTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Theme.canvas.ignoresSafeArea()

                VStack(spacing: 0) {
                    chrome
                    content
                }

                if let step = board.undoStep {
                    UndoToast(
                        step: step,
                        onUndo: {
                            undoDismissTask?.cancel()
                            Task { await board.undo() }
                        },
                        onDismiss: { board.dismissUndo() }
                    )
                    .padding(.bottom, Theme.Spacing.l)
                }
            }
            .navigationTitle("Board")
            .toolbar { toolbar }
            .toolbarBackground(Theme.canvas, for: .navigationBar)
        }
        .tint(Theme.accent)
        .animation(Theme.motion, value: board.undoStep)
        .sheet(item: $editor) { mode in
            editorSheet(for: mode)
        }
        .task { board.start() }
        .onChange(of: board.undoStep) { _, step in
            scheduleUndoDismissal(for: step)
        }
        #if DEBUG
        .sheet(isPresented: $isShowingDebug) {
            DebugSheet(repository: simulator)
        }
        #endif
    }

    // MARK: - Chrome

    private var chrome: some View {
        VStack(alignment: .leading, spacing: 0) {
            SyncPill(snapshot: board.snapshot) {
                Task { await board.dismissError() }
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.m)

            if isSearching {
                searchField
                    .padding(.horizontal, Theme.Spacing.l)
                    .padding(.bottom, Theme.Spacing.m)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Picker("Layout", selection: $layout) {
                ForEach(Layout.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.m)
        }
        .animation(Theme.motion, value: isSearching)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textTertiary)

            TextField("Search tasks", text: $board.searchQuery)
                .font(.system(size: 14))
                .autocorrectionDisabled()

            if board.isFiltering {
                Button {
                    withAnimation(Theme.quickMotion) { board.clearFilters() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 36)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.control))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.control)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                withAnimation(Theme.motion) { isSearching.toggle() }
                if !isSearching { board.clearFilters() }
            } label: {
                Image(systemName: isSearching ? "magnifyingglass.circle.fill" : "magnifyingglass")
            }
            .accessibilityLabel("Search")
        }

        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Section("Filter") {
                    ForEach(TaskStatus.ordered) { status in
                        Button {
                            board.toggleFilter(status)
                            if !isSearching { withAnimation(Theme.motion) { isSearching = true } }
                        } label: {
                            Label(
                                status.title,
                                systemImage: board.statusFilter.contains(status) ? "checkmark.circle.fill" : "circle"
                            )
                        }
                    }
                }

                if board.isFiltering {
                    Button("Clear filters", systemImage: "xmark.circle") {
                        withAnimation(Theme.motion) { board.clearFilters() }
                    }
                }

                #if DEBUG
                Divider()
                Button("Developer", systemImage: "ladybug") { isShowingDebug = true }
                #endif
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("More")
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button {
                editor = .create(.todo)
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("New task")
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch board.phase {
        case .loading:
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .failed(let message):
            // Only when the cache is empty; otherwise the board renders and the
            // failure degrades to the pill.
            BoardEmptyState(
                symbol: "exclamationmark.triangle",
                tint: Theme.danger,
                title: "Couldn't load your board",
                message: message,
                actionTitle: "Try again",
                isProminent: false,
                footnote: "Anything you create now is still saved and will sync later.",
                action: { Task { await board.dismissError() } }
            )

        case .ready:
            if board.isBoardEmpty {
                BoardEmptyState(
                    symbol: "rectangle.split.3x1",
                    tint: Theme.accent,
                    title: "Your board is empty",
                    message: "Add a task and drag it across To Do, In Progress and Done as the work moves.",
                    actionTitle: "Create your first task",
                    footnote: "Works offline — changes sync when you reconnect.",
                    action: { editor = .create(.todo) }
                )
            } else if board.hasNoMatches {
                BoardEmptyState(
                    symbol: "magnifyingglass",
                    tint: Theme.textSecondary,
                    title: "No matches",
                    message: "Nothing here matches your search and filters.",
                    actionTitle: "Clear filters",
                    isProminent: false,
                    action: { withAnimation(Theme.motion) { board.clearFilters() } }
                )
            } else {
                switch layout {
                case .board:
                    BoardColumnsView(
                        columns: board.columns,
                        syncState: board.syncState,
                        onMove: { id, status, index in
                            Task { await board.move(id, to: status, targetIndex: index) }
                        },
                        onSelect: { editor = .edit($0) },
                        onAdd: { editor = .create($0) }
                    )
                    .transition(.opacity)

                case .list:
                    TaskListView(
                        columns: board.columns,
                        syncState: board.syncState,
                        onMove: { id, status, index in
                            Task { await board.move(id, to: status, targetIndex: index) }
                        },
                        onSelect: { editor = .edit($0) },
                        onDelete: { id in Task { await board.delete(id) } }
                    )
                    .transition(.opacity)
                }
            }
        }
    }

    @ViewBuilder
    private func editorSheet(for mode: TaskEditorSheet.Mode) -> some View {
        switch mode {
        case .create(let status):
            TaskEditorSheet(mode: .create(status)) { title, details, chosen in
                Task { await board.createTask(title: title, details: details, status: chosen) }
            }

        case .edit(let task):
            // Re-read so the sheet reflects changes that arrived while it was open.
            let current = board.task(task.id) ?? task
            TaskEditorSheet(
                mode: .edit(current),
                syncState: board.syncState(for: current),
                onSave: { title, details, status in
                    Task {
                        await board.updateTask(current.id, title: title, details: details)
                        if status != current.status {
                            await board.move(current.id, to: status, targetIndex: .max)
                        }
                    }
                },
                onDelete: { Task { await board.delete(current.id) } }
            )
        }
    }

    private func scheduleUndoDismissal(for step: BoardViewModel.UndoStep?) {
        undoDismissTask?.cancel()
        guard step != nil else { return }
        undoDismissTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            board.dismissUndo()
        }
    }
}

extension TaskEditorSheet.Mode: Identifiable {
    var id: String {
        switch self {
        case .create(let status): "create-\(status.rawValue)"
        case .edit(let task): "edit-\(task.id)"
        }
    }
}
