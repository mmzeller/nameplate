import AppKit
import NameplateCore

/// Preference keys, stored as ordinary user defaults in the `com.mmzeller.Nameplate` domain.
enum PrefKey {
    // What is shown, and in what order (JSON).
    static let layout = "Layout"

    // Desktop placement
    static let showOnDesktop = "ShowOnDesktop"
    static let desktopPosition = "DesktopPosition"
    static let desktopScreens = "DesktopScreens"
    static let marginX = "DesktopMarginX"
    static let marginY = "DesktopMarginY"
    static let displayPlacements = "DisplayPlacements"  // display key -> {corner, x, y}
    static let displayNames = "DisplayNames"            // display key -> name, for displays not connected right now

    // Desktop look
    static let fontFamily = "FontFamily"
    static let fontSize = "FontSize"
    static let fontWeight = "FontWeight"
    static let lineSpacing = "LineSpacing"
    static let textColor = "TextColor"          // light | dark | custom
    static let customColor = "CustomTextColor"  // #RRGGBB
    static let labelColor = "LabelColor"        // "" = dimmed text color, or #RRGGBB
    static let headingColor = "HeadingColor"    // "" = same as labels, or #RRGGBB
    static let textOpacity = "TextOpacity"
    static let textShadow = "TextShadow"
    static let showLabels = "ShowLabels"
    static let showBars = "ShowBars"
    static let background = "Background"        // off | solid | blur
    static let backgroundColor = "BackgroundColor"
    static let backgroundOpacity = "BackgroundOpacity"
    static let backgroundCorner = "BackgroundCorner"
    static let backgroundPadding = "BackgroundPadding"
    static let savedLooks = "SavedLooks"

    // Information
    static let interfaceScope = "InterfaceScope"
    static let volumeScope = "VolumeScope"
    static let showLinkLocalIPv6 = "ShowLinkLocalIPv6"
    static let showTemporaryIPv6 = "ShowTemporaryIPv6"
    static let liveInterval = "LiveInterval"

    // Menu bar
    static let showMenuBarIcon = "ShowMenuBarIcon"      // Nameplate is in the menu bar at all
    static let menuBarShowSymbol = "MenuBarShowSymbol"  // the icon part
    static let menuBarSymbol = "MenuBarSymbol"
    static let menuBarText = "MenuBarText"              // off | ip | name | custom
    static let menuBarTemplate = "MenuBarTemplate"
    static let detachablePanel = "DetachablePanel"

    // Shortcuts ("keyCode:modifiers" or "none")
    static let copyHotKey = "CopyHotKey"
    static let panelHotKey = "PanelHotKey"
    static let toggleDesktopHotKey = "ToggleDesktopHotKey"
    static let copyIPHotKey = "CopyIPHotKey"

    static let showDockIcon = "ShowDockIcon"
    static let hasLaunched = "HasLaunchedBefore"

    // Version 1.0 settings, read once to carry them over.
    static let legacyMenuBarStyle = "MenuBarStyle"
    static let legacySectionTitles = "ShowSectionTitles"
    static func legacyItem(_ item: InfoItem) -> String { "Show." + item.rawValue }
}

enum TextColorChoice: String, CaseIterable {
    case light, dark, custom
    var title: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .custom: return "Custom"
        }
    }
}

enum BackgroundStyle: String, CaseIterable {
    case off, solid, blur
    var title: String {
        switch self {
        case .off: return "None"
        case .solid: return "Solid"
        case .blur: return "Frosted glass"
        }
    }
}

enum MenuBarText: String, CaseIterable {
    case off, ip, name, custom
    var title: String {
        switch self {
        case .off: return "Nothing (icon only)"
        case .ip: return "IP address"
        case .name: return "Computer name"
        case .custom: return "Your own text"
        }
    }
}

enum FontChoice {
    static let system = "System"
    static let systemMono = "System Monospaced"
    static let systemRounded = "System Rounded"
    static let builtIn = [system, systemMono, systemRounded]
}

enum FontWeightChoice: String, CaseIterable {
    case light, regular, medium, semibold, bold
    var title: String { rawValue.capitalized }
}

enum Prefs {
    static var defaults: UserDefaults { .standard }

    static let appearanceDefaults: [String: Any] = [
        PrefKey.fontFamily: FontChoice.system,
        PrefKey.fontSize: 12.0,
        PrefKey.fontWeight: FontWeightChoice.regular.rawValue,
        PrefKey.lineSpacing: 1.0,
        PrefKey.textColor: TextColorChoice.light.rawValue,
        PrefKey.customColor: "#FFD60A",
        PrefKey.labelColor: "",
        PrefKey.headingColor: "",
        PrefKey.textOpacity: 0.9,
        PrefKey.textShadow: true,
        PrefKey.showLabels: true,
        PrefKey.showBars: true,
        PrefKey.background: BackgroundStyle.off.rawValue,
        PrefKey.backgroundColor: "#000000",
        PrefKey.backgroundOpacity: 0.35,
        PrefKey.backgroundCorner: 12.0,
        PrefKey.backgroundPadding: 14.0,
    ]

    static func registerDefaults() {
        var values: [String: Any] = [
            PrefKey.showOnDesktop: true,
            PrefKey.desktopPosition: DesktopPosition.bottomLeft.rawValue,
            PrefKey.desktopScreens: ScreenSelection.menuBarDisplay.rawValue,
            PrefKey.marginX: 28.0,
            PrefKey.marginY: 28.0,
            PrefKey.interfaceScope: InterfaceScope.active.rawValue,
            PrefKey.volumeScope: VolumeScope.startup.rawValue,
            PrefKey.showLinkLocalIPv6: false,
            PrefKey.showTemporaryIPv6: false,
            PrefKey.liveInterval: 2.0,
            PrefKey.showMenuBarIcon: true,
            PrefKey.menuBarShowSymbol: true,
            PrefKey.menuBarSymbol: "info.circle",
            PrefKey.menuBarText: MenuBarText.off.rawValue,
            PrefKey.menuBarTemplate: "{ip}",
            PrefKey.detachablePanel: true,
            PrefKey.showDockIcon: false,
            PrefKey.copyHotKey: HotKeySpec.defaultCopy.stringValue,
            PrefKey.panelHotKey: "none",
            PrefKey.toggleDesktopHotKey: "none",
            PrefKey.copyIPHotKey: "none",
        ]
        values.merge(appearanceDefaults) { current, _ in current }
        defaults.register(defaults: values)
    }

    /// Carries settings over from version 1.0.
    static func migrate() {
        let d = defaults
        if d.string(forKey: PrefKey.layout) == nil {
            let layout = Layout.standard(
                isOn: { item in (d.object(forKey: PrefKey.legacyItem(item)) as? Bool) ?? item.defaultOn },
                headings: d.bool(forKey: PrefKey.legacySectionTitles)
            )
            saveLayout(layout)
            for item in InfoItem.allCases { d.removeObject(forKey: PrefKey.legacyItem(item)) }
            d.removeObject(forKey: PrefKey.legacySectionTitles)
        }
        if let old = d.string(forKey: PrefKey.legacyMenuBarStyle) {
            switch old {
            case "iconAndIP":
                d.set(true, forKey: PrefKey.menuBarShowSymbol)
                d.set(MenuBarText.ip.rawValue, forKey: PrefKey.menuBarText)
            case "ip":
                d.set(false, forKey: PrefKey.menuBarShowSymbol)
                d.set(MenuBarText.ip.rawValue, forKey: PrefKey.menuBarText)
            case "name":
                d.set(false, forKey: PrefKey.menuBarShowSymbol)
                d.set(MenuBarText.name.rawValue, forKey: PrefKey.menuBarText)
            default:
                break
            }
            d.removeObject(forKey: PrefKey.legacyMenuBarStyle)
        }
    }

    // MARK: Reading

    static func bool(_ key: String) -> Bool { defaults.bool(forKey: key) }
    static func string(_ key: String) -> String { defaults.string(forKey: key) ?? "" }
    static func double(_ key: String) -> Double { defaults.double(forKey: key) }

    static var showOnDesktop: Bool { bool(PrefKey.showOnDesktop) }
    static var showMenuBarIcon: Bool { bool(PrefKey.showMenuBarIcon) }
    static var showDockIcon: Bool { bool(PrefKey.showDockIcon) }
    static var menuBarText: MenuBarText { MenuBarText(rawValue: string(PrefKey.menuBarText)) ?? .off }

    static func hotKey(_ key: String) -> HotKeySpec? {
        HotKeySpec(string: string(key))
    }

    // MARK: Desktop placement

    /// Used on any display you haven't positioned the info on yourself.
    static var defaultPlacement: Placement {
        Placement(corner: DesktopPosition(rawValue: string(PrefKey.desktopPosition)) ?? .bottomLeft,
                  x: CGFloat(max(0, double(PrefKey.marginX))),
                  y: CGFloat(max(0, double(PrefKey.marginY))))
    }

    static func placements() -> [String: Placement] {
        guard let stored = defaults.dictionary(forKey: PrefKey.displayPlacements) else { return [:] }
        var result: [String: Placement] = [:]
        for (key, value) in stored {
            if let dictionary = value as? [String: Any], let placement = Placement(dictionary: dictionary) {
                result[key] = placement
            }
        }
        return result
    }

    static func placement(forDisplay key: String) -> Placement {
        placements()[key] ?? defaultPlacement
    }

    static func hasOwnPlacement(_ key: String) -> Bool {
        placements()[key] != nil
    }

    static func setPlacement(_ placement: Placement, forDisplay key: String) {
        var stored = defaults.dictionary(forKey: PrefKey.displayPlacements) ?? [:]
        stored[key] = placement.dictionary
        defaults.set(stored, forKey: PrefKey.displayPlacements)
    }

    static func removePlacement(forDisplay key: String) {
        var stored = defaults.dictionary(forKey: PrefKey.displayPlacements) ?? [:]
        stored[key] = nil
        defaults.set(stored, forKey: PrefKey.displayPlacements)
    }

    static var screenSelection: ScreenSelection {
        ScreenSelection(string(PrefKey.desktopScreens))
    }

    /// Remembers display names, so Settings can name a display that's unplugged right now.
    static func rememberDisplayNames(_ names: [String: String]) {
        var stored = (defaults.dictionary(forKey: PrefKey.displayNames) as? [String: String]) ?? [:]
        let before = stored
        stored.merge(names) { _, new in new }
        if stored != before { defaults.set(stored, forKey: PrefKey.displayNames) }
    }

    static func displayName(_ key: String) -> String? {
        (defaults.dictionary(forKey: PrefKey.displayNames) as? [String: String])?[key]
    }

    // MARK: Layout

    static func layout() -> Layout {
        var layout: Layout
        if let text = defaults.string(forKey: PrefKey.layout),
           let decoded = try? JSONDecoder().decode(Layout.self, from: Data(text.utf8)),
           !decoded.entries.isEmpty {
            layout = decoded
        } else {
            layout = .standard()
        }
        layout.addMissingItems()
        return layout
    }

    static func saveLayout(_ layout: Layout) {
        guard let data = try? JSONEncoder().encode(layout) else { return }
        let text = String(decoding: data, as: UTF8.self)
        if defaults.string(forKey: PrefKey.layout) != text {
            defaults.set(text, forKey: PrefKey.layout)
        }
    }

    static func renderSettings() -> RenderSettings {
        RenderSettings(
            interfaceScope: InterfaceScope(rawValue: string(PrefKey.interfaceScope)) ?? .active,
            volumeScope: VolumeScope(rawValue: string(PrefKey.volumeScope)) ?? .startup,
            showLinkLocalIPv6: bool(PrefKey.showLinkLocalIPv6),
            showTemporaryIPv6: bool(PrefKey.showTemporaryIPv6)
        )
    }

    // MARK: Desktop style

    static func desktopStyle() -> DesktopStyle {
        let choice = TextColorChoice(rawValue: string(PrefKey.textColor)) ?? .light
        let base: NSColor
        switch choice {
        case .light: base = .white
        case .dark: base = NSColor(white: 0.08, alpha: 1)
        case .custom: base = NSColor.fromHex(string(PrefKey.customColor)) ?? .white
        }
        return DesktopStyle(
            fontFamily: string(PrefKey.fontFamily),
            fontSize: CGFloat(min(max(double(PrefKey.fontSize), 8), 40)),
            fontWeight: string(PrefKey.fontWeight),
            textColor: base,
            labelColor: NSColor.fromHex(string(PrefKey.labelColor)),
            headingColor: NSColor.fromHex(string(PrefKey.headingColor)),
            opacity: CGFloat(min(max(double(PrefKey.textOpacity), 0.2), 1)),
            shadow: bool(PrefKey.textShadow),
            showLabels: bool(PrefKey.showLabels),
            showBars: bool(PrefKey.showBars),
            lineSpacing: CGFloat(min(max(double(PrefKey.lineSpacing), 0), 3)),
            background: BackgroundStyle(rawValue: string(PrefKey.background)) ?? .off,
            backgroundColor: NSColor.fromHex(string(PrefKey.backgroundColor)) ?? .black,
            backgroundOpacity: CGFloat(min(max(double(PrefKey.backgroundOpacity), 0), 1)),
            cornerRadius: CGFloat(min(max(double(PrefKey.backgroundCorner), 0), 40)),
            padding: CGFloat(min(max(double(PrefKey.backgroundPadding), 0), 60)),
            screens: screenSelection,
            defaultPlacement: defaultPlacement,
            placements: placements()
        )
    }
}

extension NSColor {
    static func fromHex(_ hex: String) -> NSColor? {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        return NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                       green: CGFloat((value >> 8) & 0xFF) / 255,
                       blue: CGFloat(value & 0xFF) / 255,
                       alpha: 1)
    }

    var hexString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#FFFFFF" }
        let r = Int((rgb.redComponent * 255).rounded())
        let g = Int((rgb.greenComponent * 255).rounded())
        let b = Int((rgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    var luminance: CGFloat {
        let rgb = usingColorSpace(.sRGB) ?? self
        return 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
    }
}
