import FirebaseCore
import FirebaseDatabase
import Foundation

/// Composition root. Builds the object graph once, at launch, so nothing below it
/// has to know which backend it is talking to.
@MainActor
final class AppEnvironment {

    let board: BoardViewModel
    /// Present only when running against the in-memory backend, which is what the
    /// developer sheet drives.
    let simulator: InMemoryTaskRepository?

    private init(repository: any TaskRepository, simulator: InMemoryTaskRepository?) {
        self.board = BoardViewModel(repository: repository)
        self.simulator = simulator
    }

    /// The real app: Firebase, with its local cache doing the persistence.
    ///
    /// In debug builds this defers to the simulated backend when the developer
    /// sheet has asked for it. Choosing the backend at launch rather than swapping
    /// it live keeps the decision in one place — a running board cannot end up half
    /// attached to each.
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

    /// Everything in memory, with the network knobs exposed. Used by previews and
    /// by the developer sheet's "use in-memory backend" switch.
    static func simulated(
        tasks: [BoardTask] = [],
        conditions: InMemoryTaskRepository.Conditions = .perfect
    ) -> AppEnvironment {
        let repository = InMemoryTaskRepository(tasks: tasks, conditions: conditions)
        return AppEnvironment(repository: repository, simulator: repository)
    }
}

/// Firebase setup, kept in one place because the ordering is load-bearing.
enum FirebaseBootstrap {

    /// Configures Firebase and returns the database handle.
    ///
    /// `isPersistenceEnabled` has to be set before *any* `DatabaseReference` is
    /// created — set it afterwards and the SDK throws at runtime. That is the whole
    /// reason this runs from `App.init()` rather than from a view's `.task`.
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

    /// Run against `InMemoryTaskRepository` instead of Firebase, so the network and
    /// failure knobs in the developer sheet have something to act on.
    ///
    /// Also settable from the command line — `-debug.useSimulatedBackend YES` in the
    /// scheme's arguments — which is how a reviewer can reach the simulated backend
    /// without first launching into the real one.
    static var useSimulatedBackend: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
#endif
