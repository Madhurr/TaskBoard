import SwiftUI

/// A single task, as it appears on the board.
struct TaskCardView: View {
    let task: BoardTask
    let syncState: SyncState
    var isCompact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 9) {
                Text(task.title)
                    .font(.system(size: isCompact ? 14 : 14.5, weight: .medium))
                    .kerning(-0.17)
                    .foregroundStyle(task.status == .done ? Theme.textSecondary : Theme.textPrimary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                SyncBadge(state: syncState)
            }

            if task.hasDetails {
                Text(task.details)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .padding(.top, 5)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(stamp)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
                .padding(.top, 9)
        }
        .padding(.vertical, 12)
        .padding(.trailing, 13)
        .padding(.leading, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .leading) {
            // The column's hue, carried onto the card, so a card in mid-drag stays
            // visually attached to where it came from.
            Rectangle()
                .fill(task.status.accent)
                .frame(width: 3)
        }
        .cardSurface()
        .contentShape(.rect(cornerRadius: Theme.Radius.card))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    /// "Saving…" replaces the timestamp while a write is outstanding: the moment the
    /// user most wants to know the state of a task is the moment it is in flight,
    /// and that is exactly when "updated 0m ago" says nothing useful.
    private var stamp: String {
        switch syncState {
        case .pending: "Saving…"
        case .queuedOffline: "Waiting for connection"
        case .synced: "Updated \(task.updatedAt.formatted(.relative(presentation: .numeric)))"
        }
    }

    private var accessibilityText: String {
        var parts = [task.title, task.status.title]
        if task.hasDetails { parts.append(task.details) }
        if syncState != .synced { parts.append(syncState.accessibilityLabel) }
        return parts.joined(separator: ", ")
    }
}

/// The per-card sync mark.
///
/// A synced task shows nothing at all — the absence of a badge is the signal, which
/// keeps a board full of unsynced work reading as a board rather than as a wall of
/// warnings.
struct SyncBadge: View {
    let state: SyncState
    @State private var isPulsing = false

    var body: some View {
        Group {
            switch state {
            case .synced:
                EmptyView()

            case .pending:
                Circle()
                    .fill(Theme.warning)
                    .frame(width: 7, height: 7)
                    .overlay {
                        Circle()
                            .stroke(Theme.warning.opacity(0.28), lineWidth: 3)
                            .scaleEffect(isPulsing ? 1.9 : 1.2)
                            .opacity(isPulsing ? 0 : 1)
                    }
                    .padding(.top, 4)
                    .padding(.trailing, 3)
                    .onAppear {
                        withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) {
                            isPulsing = true
                        }
                    }

            case .queuedOffline:
                // Secondary grey, not a warning colour: being offline is an
                // expected mode of this app, not a fault to alarm anyone about.
                Image(systemName: "icloud.slash")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 1)
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview("Card states") {
    let now = Date()
    return ScrollView {
        VStack(spacing: 14) {
            TaskCardView(
                task: BoardTask(title: "Draft the Q3 roadmap", position: 0, createdAt: now, updatedAt: now),
                syncState: .synced
            )
            TaskCardView(
                task: BoardTask(
                    title: "Fix the onboarding crash",
                    details: "Only reproduces on iOS 26 when the keyboard is already up.",
                    position: 0, createdAt: now, updatedAt: now
                ),
                syncState: .pending
            )
            TaskCardView(
                task: BoardTask(title: "Book the venue", status: .inProgress, position: 0, createdAt: now, updatedAt: now),
                syncState: .queuedOffline
            )
            TaskCardView(
                task: BoardTask(title: "Ship the 2.4.1 hotfix", status: .done, position: 0, createdAt: now, updatedAt: now),
                syncState: .synced
            )
        }
        .padding()
    }
    .background(Theme.canvas)
}
