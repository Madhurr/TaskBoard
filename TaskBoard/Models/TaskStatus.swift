import SwiftUI

/// The three columns of the board. Raw values are the wire format stored in
/// Realtime Database — never rename them without a migration.
enum TaskStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case todo
    case inProgress
    case done

    var id: String { rawValue }

    var title: String {
        switch self {
        case .todo: "To Do"
        case .inProgress: "In Progress"
        case .done: "Done"
        }
    }

    var symbolName: String {
        switch self {
        case .todo: "tray"
        case .inProgress: "circle.dotted"
        case .done: "checkmark.circle"
        }
    }

    /// Column accent, carried onto each card's leading stripe.
    var accent: Color {
        switch self {
        case .todo: Color(red: 0.42, green: 0.55, blue: 0.98)
        case .inProgress: Color(red: 0.98, green: 0.68, blue: 0.31)
        case .done: Color(red: 0.30, green: 0.80, blue: 0.60)
        }
    }

    /// Display order, left to right.
    static let ordered: [TaskStatus] = [.todo, .inProgress, .done]
}
