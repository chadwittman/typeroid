import Foundation

/// The line on the pill above the Dock. Short, on purpose.
public enum JuiceCue: Equatable, Sendable {
    case rest
    case benched
    case juicing
    case openSet
    case cooking
    case gains
    case spit
    case hint
    case access

    public var label: String {
        switch self {
        case .rest: "hold fn"
        case .benched: "off cycle"
        case .juicing: "listening"
        case .openSet: "hands-free"
        case .cooking: "typemaxxing"
        case .gains: "grown-up"
        case .spit: "no juice"
        case .hint: "keep holding"
        case .access: "allow fn"
        }
    }

    /// Map a menu-bar status string onto the pill. Empty means back to rest.
    public static func from(status: String) -> JuiceCue {
        let text = status.lowercased()
        if text.isEmpty { return .rest }
        if text.contains("fn on") { return .openSet }
        if text.contains("listen") { return .juicing }
        if text.contains("hold fn") || text.contains("hold to") || text.contains("hold it") { return .hint }
        if text.contains("cancel") { return .spit }
        if text.contains("input monitoring") || text.contains("accessibility") || text.contains("monitor failed") {
            return .access
        }
        if text.contains("won't") || text.contains("failed") || text.contains("needs ")
            || text.contains("no api") || text.contains("no speech") || text.contains("nothing")
            || text.contains("disabled") || text.contains("blocked") || text.contains("busy")
            || text.contains("permission") || text.contains("isn't running")
            || text.contains("not running") || text.contains("keychain") {
            return .spit
        }
        if text.contains("done") || text.contains("looks good") || text.contains("copied")
            || text.contains("it works") || text.contains("undone") || text.contains("key saved")
            || text.contains("ready") {
            return .gains
        }
        return .cooking
    }
}
