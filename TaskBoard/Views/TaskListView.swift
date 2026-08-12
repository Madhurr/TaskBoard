import SwiftUI

/// List mode: the same data under a different geometry.
///
/// It exists because a three-column board on a 390pt screen is a poor way to read
/// twenty tasks in a row. Reordering within a section is a long-press drag; moving
/// between sections is done from the editor, which keeps the gesture unambiguous.
struct TaskListView: View {
    let columns: [(status: TaskStatus, tasks: [BoardTask])]
    let syncState: (BoardTask) -> SyncState
    let onMove: (BoardTask.ID, TaskStatus, Int) -> Void
    let onSelect: (BoardTask) -> Void
    let onDelete: (BoardTask.ID) -> Void

    var body: some View {
        List {
            ForEach(columns, id: \.status) { column in
                if !column.tasks.isEmpty {
                    Section {
                        ForEach(column.tasks) { task in
                            TaskRow(task: task, syncState: syncState(task))
                                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                                .listRowBackground(Theme.surface)
                                .contentShape(.rect)
                                .onTapGesture { onSelect(task) }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        onDelete(task.id)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                        .onMove { offsets, destination in
                            move(in: column, from: offsets, to: destination)
                        }
                    } header: {
                        header(for: column.status, count: column.tasks.count)
                    }
                }
            }

            // Keeps the last row clear of the floating button.
            Color.clear
                .frame(height: 72)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .environment(\.defaultMinListRowHeight, 0)
    }

    private func header(for status: TaskStatus, count: Int) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            Circle()
                .fill(status.accent)
                .frame(width: 8, height: 8)

            Text(status.title.uppercased())
                .font(.system(size: 11.5, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(Theme.textSecondary)

            Spacer()

            Text("\(count)")
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.bottom, 2)
        .textCase(nil)
    }

    /// Translates SwiftUI's pre-move offsets into a destination index that excludes
    /// the task being moved, which is the contract `BoardLogic.move` expects.
    private func move(in column: (status: TaskStatus, tasks: [BoardTask]), from offsets: IndexSet, to destination: Int) {
        guard let source = offsets.first, source < column.tasks.count else { return }
        let task = column.tasks[source]
        let target = destination > source ? destination - 1 : destination
        onMove(task.id, column.status, target)
    }
}

private struct TaskRow: View {
    let task: BoardTask
    let syncState: SyncState

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Rectangle()
                .fill(task.status.accent)
                .frame(width: 3)
                .clipShape(.rect(cornerRadius: 1.5))

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.system(size: 14, weight: .medium))
                    .kerning(-0.17)
                    .foregroundStyle(task.status == .done ? Theme.textSecondary : Theme.textPrimary)
                    .lineLimit(2)

                if task.hasDetails {
                    Text(task.details)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            SyncBadge(state: syncState)
        }
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }
}
