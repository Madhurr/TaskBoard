import SwiftUI

/// Create or edit a task. Status is editable here as well as by dragging, since
/// list mode has no cross-section gesture.
struct TaskEditorSheet: View {

    enum Mode: Equatable {
        case create(TaskStatus)
        case edit(BoardTask)

        var isEditing: Bool { if case .edit = self { true } else { false } }
    }

    let mode: Mode
    let syncState: SyncState
    let onSave: (String, String, TaskStatus) -> Void
    let onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var details: String
    @State private var status: TaskStatus
    @State private var isConfirmingDelete = false
    @FocusState private var isTitleFocused: Bool

    init(
        mode: Mode,
        syncState: SyncState = .synced,
        onSave: @escaping (String, String, TaskStatus) -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.mode = mode
        self.syncState = syncState
        self.onSave = onSave
        self.onDelete = onDelete

        switch mode {
        case .create(let status):
            _title = State(initialValue: "")
            _details = State(initialValue: "")
            _status = State(initialValue: status)
        case .edit(let task):
            _title = State(initialValue: task.title)
            _details = State(initialValue: task.details)
            _status = State(initialValue: task.status)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    field("Title") {
                        TextField("What needs doing?", text: $title, axis: .vertical)
                            .font(.system(size: 15))
                            .focused($isTitleFocused)
                            .lineLimit(1...3)
                            .submitLabel(.done)
                    }

                    field("Description") {
                        TextField("Add any detail worth keeping", text: $details, axis: .vertical)
                            .font(.system(size: 14))
                            .lineLimit(4...8)
                            .frame(minHeight: 76, alignment: .topLeading)
                    }

                    label("Status")
                    HStack(spacing: 6) {
                        ForEach(TaskStatus.ordered) { option in
                            statusOption(option)
                        }
                    }
                    .padding(.bottom, 22)

                    if let onDelete {
                        Button(role: .destructive) {
                            isConfirmingDelete = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "trash")
                                Text("Delete task")
                            }
                            .font(.system(size: 14.5, weight: .medium))
                            .foregroundStyle(Theme.danger)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background {
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Theme.danger.opacity(0.32), lineWidth: 1)
                            }
                        }
                        .confirmationDialog(
                            "Delete this task?",
                            isPresented: $isConfirmingDelete,
                            titleVisibility: .visible
                        ) {
                            Button("Delete", role: .destructive) {
                                onDelete()
                                dismiss()
                            }
                        } message: {
                            Text("You can undo this straight after.")
                        }
                    }

                    if case .edit(let task) = mode {
                        metadata(for: task)
                    }
                }
                .padding(Theme.Spacing.l)
            }
            .background(Theme.canvasElevated)
            .navigationTitle(mode.isEditing ? "Edit task" : "New task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(title, details, status)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!BoardLogic.isValid(title: title))
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            // New tasks only — on an existing one the keyboard hides the content.
            if case .create = mode { isTitleFocused = true }
        }
    }

    private func statusOption(_ option: TaskStatus) -> some View {
        Button {
            withAnimation(Theme.quickMotion) { status = option }
        } label: {
            Text(option.title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(status == option ? option.accent : Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(
                    status == option ? option.accent.opacity(0.14) : Theme.surface,
                    in: .rect(cornerRadius: 11)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 11)
                        .strokeBorder(
                            status == option ? option.accent.opacity(0.5) : Theme.hairline,
                            lineWidth: 1
                        )
                }
        }
        .buttonStyle(.plain)
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .kerning(0.66)
            .foregroundStyle(Theme.textTertiary)
            .padding(.bottom, 7)
    }

    private func field<Content: View>(_ name: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            label(name)
            content()
                .padding(.horizontal, 13)
                .padding(.vertical, 12)
                .background(Theme.surface, in: .rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Theme.hairline, lineWidth: 1)
                }
                .padding(.bottom, 18)
        }
    }

    /// Says plainly whether this task has reached the server.
    private func metadata(for task: BoardTask) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Divider().overlay(Theme.hairline).padding(.bottom, 11)

            Text("Created \(task.createdAt.formatted(date: .abbreviated, time: .shortened))")
            HStack(spacing: 4) {
                Text("Last updated \(task.updatedAt.formatted(.relative(presentation: .numeric)))")
                Text("·")
                Text(syncState.accessibilityLabel)
                    .foregroundStyle(syncState == .synced ? Theme.success : Theme.warning)
            }
        }
        .font(.system(size: 11.5))
        .foregroundStyle(Theme.textTertiary)
        .padding(.top, 16)
    }
}
