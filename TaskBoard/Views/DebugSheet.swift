import SwiftUI

#if DEBUG
/// Simulates network and sync conditions. Drives the same in-memory repository
/// the tests use.
///
/// On Firebase there is nothing to fake from outside — the SDK owns its queue — so
/// the sheet offers to relaunch onto the simulated backend instead.
struct DebugSheet: View {
    let repository: InMemoryTaskRepository?

    @Environment(\.dismiss) private var dismiss
    @State private var conditions = InMemoryTaskRepository.Conditions.perfect
    @State private var latencyMilliseconds: Double = 0
    @State private var failurePercent: Double = 0
    @State private var pendingCount = 0
    @State private var useSimulated = DebugSettings.useSimulatedBackend

    var body: some View {
        NavigationStack {
            Form {
                backendSection

                if let repository {
                    connectionSection
                    serverSection
                    statusSection(repository)
                }
            }
            .navigationTitle("Developer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await load() }
        .onChange(of: conditions) { _, new in apply(new) }
        .onChange(of: latencyMilliseconds) { _, new in
            conditions.latency = .milliseconds(Int(new))
        }
        .onChange(of: failurePercent) { _, new in
            conditions.failureRate = new / 100
        }
        .onChange(of: useSimulated) { _, new in
            DebugSettings.useSimulatedBackend = new
        }
    }

    private var backendSection: some View {
        Section {
            Toggle("Use simulated backend", isOn: $useSimulated)
        } header: {
            Text("Backend")
        } footer: {
            Text(
                repository == nil
                    ? "Currently on Firebase. Switch on and relaunch to get an in-memory backend with the network controls below — Firebase owns its own write queue, so there is no honest way to fake it from here."
                    : "Currently simulated. Switch off and relaunch to go back to Firebase."
            )
        }
    }

    private var connectionSection: some View {
        Section {
            Toggle("Force offline", isOn: Binding(
                get: { !conditions.isOnline },
                set: { conditions.isOnline = !$0 }
            ))
        } header: {
            Text("Connection")
        } footer: {
            Text("Writes are accepted and held locally, exactly as they are with no network. Turning this off replays everything queued.")
        }
    }

    private var serverSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("Latency") {
                    Text("\(Int(latencyMilliseconds)) ms").monospaced()
                }
                Slider(value: $latencyMilliseconds, in: 0...3000, step: 100)
            }

            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("Failure rate") {
                    Text("\(Int(failurePercent))%").monospaced()
                }
                Slider(value: $failurePercent, in: 0...100, step: 5)
            }
        } header: {
            Text("Server behaviour")
        } footer: {
            Text("A rejected write keeps the local copy and surfaces an error — no user work is discarded.")
        }
    }

    private func statusSection(_ repository: InMemoryTaskRepository) -> some View {
        Section {
            LabeledContent("Outstanding writes") {
                Text("\(pendingCount)").monospaced()
            }
            Button("Refresh") {
                Task { pendingCount = await repository.outstandingWrites }
            }
        }
    }

    private func load() async {
        guard let repository else { return }
        conditions = await repository.currentConditions
        latencyMilliseconds = Double(conditions.latency.components.seconds) * 1000
        failurePercent = conditions.failureRate * 100
        pendingCount = await repository.outstandingWrites
    }

    private func apply(_ new: InMemoryTaskRepository.Conditions) {
        guard let repository else { return }
        Task {
            await repository.setConditions(new)
            pendingCount = await repository.outstandingWrites
        }
    }
}
#endif
