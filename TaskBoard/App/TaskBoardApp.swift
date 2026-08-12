import SwiftUI

@main
struct TaskBoardApp: App {

    @State private var environment: AppEnvironment

    init() {
        // The unit tests are hosted by this app, so this runs before they do —
        // booting Firebase would point the suite at a live database.
        _environment = State(initialValue: Self.isRunningTests ? .simulated() : .live())
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    var body: some Scene {
        WindowGroup {
            BoardScreen(board: environment.board, simulator: environment.simulator)
                .preferredColorScheme(nil)
        }
    }
}

#Preview("Board") {
    let environment = AppEnvironment.simulated(tasks: BoardTask.samples)
    return BoardScreen(board: environment.board, simulator: environment.simulator)
}

#Preview("Empty") {
    let environment = AppEnvironment.simulated()
    return BoardScreen(board: environment.board, simulator: environment.simulator)
}

#Preview("Offline") {
    let environment = AppEnvironment.simulated(tasks: BoardTask.samples, conditions: .offline)
    return BoardScreen(board: environment.board, simulator: environment.simulator)
}

extension BoardTask {
    static var samples: [BoardTask] {
        let now = Date()
        func task(_ title: String, _ details: String, _ status: TaskStatus, _ position: Double, _ age: TimeInterval) -> BoardTask {
            BoardTask(
                title: title, details: details, status: status, position: position,
                createdAt: now.addingTimeInterval(-age), updatedAt: now.addingTimeInterval(-age)
            )
        }
        return [
            task("Draft the Q3 roadmap", "Pull the funnel metrics from the dashboard before writing anything down.", .todo, 0, 120),
            task("Fix the onboarding crash", "Only reproduces on iOS 26 with the keyboard already up.", .todo, 1024, 1080),
            task("Book the venue for the offsite", "", .todo, 2048, 3600),
            task("Redesign the sync indicator", "Per-card marks beat a global banner.", .inProgress, 0, 720),
            task("Migrate to Swift 6", "", .inProgress, 1024, 10800),
            task("Ship the 2.4.1 hotfix", "", .done, 0, 86400),
        ]
    }
}
