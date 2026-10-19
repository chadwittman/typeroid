import Foundation

/// Which tool is working while the pill zaps.
public enum JuiceZap: Equatable, Sendable {
    case voice
    case fix
    case math
    case ask
    case translate
    case rephrase
    case screen
    case thread
    case charge
}

/// The line on the pill above the Dock. Short, on purpose.
public enum JuiceCue: Equatable, Sendable {
    case rest
    case benched
    case juicing
    case openSet
    case cooking(JuiceZap)
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
        return .cooking(zap(for: text))
    }

    /// The symbol at the front of a status line picks the zap.
    static func zap(for text: String) -> JuiceZap {
        if text.hasPrefix("fn") || text.contains("transcrib") || text.contains("cooking") {
            return .voice
        }
        if text.hasPrefix("//") { return .fix }
        if text.hasPrefix("==") { return .math }
        if text.hasPrefix("??") { return .ask }
        if text.hasPrefix(";;") { return .translate }
        if text.hasPrefix("||") { return .rephrase }
        if text.hasPrefix(">>") { return .screen }
        if text.hasPrefix("\\") { return .thread }
        return .charge
    }
}
