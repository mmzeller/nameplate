import AppKit
import NameplateCore

/// Which displays show the desktop info.
enum ScreenSelection: Equatable {
    case menuBarDisplay
    case every
    case display(String)

    init(_ raw: String) {
        if raw == "all" {
            self = .every
        } else if raw.hasPrefix("display:") {
            self = .display(String(raw.dropFirst("display:".count)))
        } else {
            self = .menuBarDisplay
        }
    }

    var rawValue: String {
        switch self {
        case .menuBarDisplay: return "main"
        case .every: return "all"
        case .display(let key): return "display:" + key
        }
    }
}

/// The connected displays, each with a key that stays the same when it's unplugged and
/// plugged back in, or its resolution changes.
@MainActor
enum Displays {
    struct Info: Identifiable, Equatable {
        let key: String
        let name: String
        let screen: NSScreen
        let hasMenuBar: Bool
        var id: String { key }
    }

    static func all() -> [Info] {
        var used: [String: Int] = [:]
        var result: [Info] = []
        for (index, screen) in NSScreen.screens.enumerated() {
            var key = baseKey(for: screen)
            let count = used[key, default: 0]
            used[key] = count + 1
            if count > 0 { key += "#\(count + 1)" }
            result.append(Info(key: key, name: screen.localizedName, screen: screen, hasMenuBar: index == 0))
        }
        return result
    }

    /// The display under `point`, or the closest one.
    static func info(containing point: NSPoint) -> Info? {
        let list = all()
        if let hit = list.first(where: { $0.screen.frame.contains(point) }) { return hit }
        return list.min { distance(from: point, to: $0.screen.frame) < distance(from: point, to: $1.screen.frame) }
    }

    private static func distance(from point: NSPoint, to rect: NSRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }

    private static func baseKey(for screen: NSScreen) -> String {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return screen.localizedName
        }
        let id = CGDirectDisplayID(number.uint32Value)
        return "\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))-\(CGDisplaySerialNumber(id))"
    }
}
