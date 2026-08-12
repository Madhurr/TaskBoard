import SwiftUI

/// The three columns, side by side and horizontally paged.
struct BoardColumnsView: View {
    let columns: [(status: TaskStatus, tasks: [BoardTask])]
    let syncState: (BoardTask) -> SyncState
    let onMove: (BoardTask.ID, TaskStatus, Int) -> Void
    let onSelect: (BoardTask) -> Void
    let onAdd: (TaskStatus) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                ForEach(columns, id: \.status) { column in
                    BoardColumnView(
                        status: column.status,
                        tasks: column.tasks,
                        syncState: syncState,
                        onDrop: { id, index in onMove(id, column.status, index) },
                        onSelect: onSelect,
                        onAdd: { onAdd(column.status) }
                    )
                    .frame(width: Theme.columnWidth)
                }
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.bottom, 96)
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollClipDisabled()
    }
}

struct BoardColumnView: View {
    let status: TaskStatus
    let tasks: [BoardTask]
    let syncState: (BoardTask) -> SyncState
    let onDrop: (BoardTask.ID, Int) -> Void
    let onSelect: (BoardTask) -> Void
    let onAdd: () -> Void

    @State private var cardFrames: [BoardTask.ID: CGRect] = [:]
    @State private var isTargeted = false

    private var coordinateSpace: NamedCoordinateSpace { .named("column-\(status.rawValue)") }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            header

            LazyVStack(spacing: Theme.Spacing.s) {
                ForEach(tasks) { task in
                    TaskCardView(task: task, syncState: syncState(task))
                        .onTapGesture { onSelect(task) }
                        .background {
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: CardFramesKey.self,
                                    value: [task.id: proxy.frame(in: coordinateSpace)]
                                )
                            }
                        }
                        .draggable(task.id) {
                            TaskCardView(task: task, syncState: syncState(task))
                                .frame(width: Theme.columnWidth - 24)
                                .rotationEffect(.degrees(-1.6))
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }

                if tasks.isEmpty {
                    emptyColumnSlot
                }
            }
            .frame(maxWidth: .infinity)
            // A generous tail so the column stays a drop target below its last card.
            .padding(.bottom, 60)
        }
        .padding(Theme.Spacing.m)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.canvasElevated, in: .rect(cornerRadius: Theme.Radius.column))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.column)
                .strokeBorder(isTargeted ? status.accent.opacity(0.55) : Theme.hairline, lineWidth: isTargeted ? 1.5 : 1)
        }
        .coordinateSpace(coordinateSpace)
        .onPreferenceChange(CardFramesKey.self) { cardFrames = $0 }
        .dropDestination(for: String.self) { items, location in
            guard let id = items.first else { return false }
            onDrop(id, insertionIndex(for: id, at: location))
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            return true
        } isTargeted: { targeted in
            withAnimation(Theme.quickMotion) { isTargeted = targeted }
        }
        .animation(Theme.motion, value: tasks.map(\.id))
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.s) {
            Circle()
                .fill(status.accent)
                .frame(width: 8, height: 8)

            Text(status.title)
                .font(.system(size: 13.5, weight: .semibold))
                .kerning(-0.16)
                .foregroundStyle(Theme.textPrimary)

            Spacer(minLength: 0)

            Text("\(tasks.count)")
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .frame(minWidth: 21, minHeight: 21)
                .padding(.horizontal, 6)
                .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.pill))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.pill)
                        .strokeBorder(Theme.hairline, lineWidth: 1)
                }
                .contentTransition(.numericText())
                .animation(Theme.quickMotion, value: tasks.count)

            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 22, height: 22)
                    .contentShape(.rect)
            }
            .accessibilityLabel("Add task to \(status.title)")
        }
        .padding(.horizontal, 3)
        .padding(.bottom, 2)
    }

    private var emptyColumnSlot: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.card)
            .strokeBorder(
                status.accent.opacity(isTargeted ? 0.5 : 0.2),
                style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
            )
            .frame(height: 74)
            .overlay {
                Text("Drop a task here")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textTertiary)
            }
    }

    /// Where the dragged card should land, from the drop point.
    ///
    /// Measured against the recorded midpoints of the *other* cards — the dragged
    /// task is excluded because `BoardLogic.move` expects an index into the column
    /// without it, which is also the only reading that makes "drop below yourself"
    /// mean anything.
    private func insertionIndex(for draggedID: BoardTask.ID, at location: CGPoint) -> Int {
        tasks
            .filter { $0.id != draggedID }
            .filter { (cardFrames[$0.id]?.midY ?? .greatestFiniteMagnitude) < location.y }
            .count
    }
}

private struct CardFramesKey: PreferenceKey {
    static let defaultValue: [BoardTask.ID: CGRect] = [:]
    static func reduce(value: inout [BoardTask.ID: CGRect], nextValue: () -> [BoardTask.ID: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}
