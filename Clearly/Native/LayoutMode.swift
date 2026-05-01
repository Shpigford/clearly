import Foundation

/// Selects between the classic two-pane shell (sidebar + editor) and a
/// Notes-style three-pane shell (sidebar + note list + editor). Persisted as
/// a raw string under `@AppStorage("layoutMode")`.
enum LayoutMode: String, CaseIterable, Identifiable {
    case twoPane
    case threePane

    var id: String { rawValue }

    static let storageKey = "layoutMode"

    var displayName: String {
        switch self {
        case .twoPane: "Two pane"
        case .threePane: "Three pane (Notes-style)"
        }
    }
}
