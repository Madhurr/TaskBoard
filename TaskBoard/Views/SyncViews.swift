import SwiftUI

/// The one-line sync summary under the title.
///
/// Counts are always concrete — a number, never "some" — because the only useful
/// version of this message is one the user can act on.
struct SyncPill: View {
    let snapshot: RepositorySnapshot
    let onRetry: () -> Void

    var body: some View {
        Button(action: { if snapshot.sync.lastError != nil { onRetry() } }) {
            HStack(spacing: 6) {
                icon
                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .kerning(-0.07)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(tint.opacity(0.13), in: .rect(cornerRadius: Theme.Radius.pill))
            .contentShape(.rect(cornerRadius: Theme.Radius.pill))
        }
        .buttonStyle(.plain)
        .disabled(snapshot.sync.lastError == nil)
        .animation(Theme.motion, value: message)
        .accessibilityLabel(message)
    }

    @ViewBuilder
    private var icon: some View {
        if snapshot.sync.lastError != nil {
            Image(systemName: "exclamationmark.circle").font(.system(size: 11.5, weight: .semibold))
        } else if !snapshot.sync.isConnected {
            Image(systemName: "icloud.slash").font(.system(size: 11.5, weight: .medium))
        } else {
            Circle().fill(tint).frame(width: 6, height: 6)
        }
    }

    private var message: String {
        if let issue = snapshot.sync.lastError {
            return issue.kind == .load ? "Couldn't reach the server" : "Couldn't save — tap to retry"
        }
        if !snapshot.sync.isConnected {
            return snapshot.hasPendingWork
                ? "Offline — \(snapshot.pendingCount) waiting"
                : "Offline"
        }
        if snapshot.hasPendingWork {
            return "Syncing \(snapshot.pendingCount) change\(snapshot.pendingCount == 1 ? "" : "s")"
        }
        return "All changes saved"
    }

    private var tint: Color {
        if snapshot.sync.lastError != nil { return Theme.danger }
        if !snapshot.sync.isConnected { return Theme.textSecondary }
        return snapshot.hasPendingWork ? Theme.warning : Theme.success
    }
}

/// Undo affordance for deletes, edits, and moves alike.
///
/// One toast covers all three because each is the same thing underneath — a set of
/// previous task versions to write back.
struct UndoToast: View {
    let step: BoardViewModel.UndoStep
    let onUndo: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 30, height: 30)
                .background(Theme.accent.opacity(0.14), in: .rect(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 1) {
                Text(step.label)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)

                if let title = step.previous.first?.title, step.previous.count == 1 {
                    Text(title)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("Undo", action: onUndo)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .cardSurface(cornerRadius: 15, elevated: true)
        .padding(.horizontal, Theme.Spacing.l)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    if value.translation.height > 20 { onDismiss() }
                }
        )
    }
}

/// Full-screen message for the states where the board has nothing to show.
struct BoardEmptyState: View {
    let symbol: String
    let tint: Color
    let title: String
    let message: String
    var actionTitle: String?
    var isProminent = true
    var footnote: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(tint)
                .frame(width: 78, height: 78)
                .background(tint.opacity(0.11), in: .rect(cornerRadius: 24))
                .overlay {
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(tint.opacity(0.26), lineWidth: 1)
                }
                .padding(.bottom, 20)

            Text(title)
                .font(.system(size: 18.5, weight: .semibold))
                .kerning(-0.33)
                .foregroundStyle(Theme.textPrimary)
                .padding(.bottom, 7)

            Text(message)
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .frame(maxWidth: 280)

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isProminent ? .white : Theme.textPrimary)
                        .padding(.horizontal, 20)
                        .frame(height: 44)
                        .background {
                            if isProminent {
                                LinearGradient(
                                    colors: [Theme.accent.opacity(0.92), Theme.accent],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                                .clipShape(.rect(cornerRadius: 13))
                            } else {
                                RoundedRectangle(cornerRadius: 13)
                                    .strokeBorder(Theme.hairline, lineWidth: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
                .padding(.top, 22)
            }

            if let footnote {
                Text(footnote)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 26)
                    .frame(maxWidth: 280)
            }
        }
        .padding(.horizontal, 34)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
