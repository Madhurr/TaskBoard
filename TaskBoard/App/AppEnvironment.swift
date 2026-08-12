import FirebaseCore
import FirebaseDatabase
import Foundation

/// Composition root. Builds the object graph once, so nothing below it knows which
/// backend it has.
@MainActor
final class AppEnvironment {

    let board: BoardViewModel
    /// Set only on the in-memory backend, which the developer sheet drives.
    let simulator: InMemoryTaskRepository?

    private init(repository: any TaskRepository, simulator: InMemoryTaskRepository?) {
        self.board = BoardViewModel(repository: repository)
        self.simulator = simulator
    }

    /// Firebase, with its local cache doing the persistence. Debug builds can
    /// divert to the simulated backend; the choice is made at launch so a running
    /// board is never half-attached to both.
    static func live() -> AppEnvironment {
        #if DEBUG
        if DebugSettings.useSimulatedBackend {
            return .simulated(tasks: BoardTask.samples)
        }
        #endif

        let database = FirebaseBootstrap.configure()
        return AppEnvironment(
            repository: FirebaseTaskRepository(database: database),
            simulator: nil
        )
    }

    /// Everything in memory, with the network knobs exposed.
    static func simulated(
        tasks: [BoardTask] = [],
        conditions: InMemoryTaskRepository.Conditions = .perfect
    ) -> AppEnvironment {
        let repository = InMemoryTaskRepository(tasks: tasks, conditions: conditions)
        return AppEnvironment(repository: repository, simulator: repository)
    }
}

enum FirebaseBootstrap {

    /// `isPersistenceEnabled` must be set before any `DatabaseReference` exists, or
    /// the SDK throws at runtime — hence calling this from `App.init()`.
    static func configure() -> Database {
        FirebaseApp.configure()

        let database = Database.database()
        database.isPersistenceEnabled = true
        return database
    }
}

#if DEBUG
/// Persisted developer preferences. Debug builds only.
enum DebugSettings {
    private static let key = "debug.useSimulatedBackend"

    /// Run against `InMemoryTaskRepository` instead of Firebase. Also settable via
    /// `-debug.useSimulatedBackend YES` in the scheme's arguments.
    static var useSimulatedBackend: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
#endif
