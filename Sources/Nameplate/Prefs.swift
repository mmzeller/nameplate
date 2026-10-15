import AppKit
import NameplateCore

/// Preference keys. They are plain user defaults in the `com.mmzeller.Nameplate` domain,
/// so an admin can set (and lock) any of them with `defaults write` or an MDM profile.
enum PrefKey {
    static let showOnDesktop = "ShowOnDesktop"
    static let desktopPosition = "DesktopPosition"
    static let desktopScreens = "DesktopScreens"
    static let marginX = "DesktopMarginX"
    static let marginY = "DesktopMarginY"
    static let fontFamily = "FontFamily"
    static let fontSize = "FontSize"
    static let fontWeight = "FontWeight"
    static let textColor = "TextColor"          // light | dark | custom
    static let customColor = "CustomTextColor"  // #RRGGBB
    static let textOpacity = "TextOpacity"
    static let textShadow = "TextShadow"
    static let showLabels = "ShowLabels"
    static let showSectionTitles = "ShowSectionTitles"

    static let interfaceScope = "InterfaceScope"
    static let volumeScope = "VolumeScope"
    static let showLinkLocalIPv6 = "ShowLinkLocalIPv6"
    static let showTemporaryIPv6 = "ShowTemporaryIPv6"

    static let showMenuBarIcon = "ShowMenuBarIcon"
    static let menuBarStyle = "MenuBarStyle"    // icon | iconAndIP | ip | name
    static let menuBarSymbol = "MenuBarSymbol"
    static let detachablePanel = "DetachablePanel"

    static let showDockIcon = "ShowDockIcon"
    static let copyHotKey = "CopyHotKey"
    static let panelHotKey = "PanelHotKey"
    static let launchAtLogin = "LaunchAtLogin"  // only applied when set by an admin / MDM
    static let labMode = "LabMode"
    static let hasLaunched = "HasLaunchedBefore"

    static func item(_ item: InfoItem) -> String { "Show." + item.rawValue }
}

enum DesktopPosition: String, CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight
    var title: String {
        switch self {
        case .topLeft: return "Top left"
        case .topRight: return "Top right"
        case .bottomLeft: return "Bottom left"
        case .bottomRight: return "Bottom right"
        }
    }
}

enum ScreenChoice: String, CaseIterable {
    case main, all
    var title: String { self == .main ? "Main display" : "Every display" }
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

enum MenuBarStyle: String, CaseIterable {
    case icon, iconAndIP, ip, name
    var title: String {
        switch self {
        case .icon: return "Icon"
        case .iconAndIP: return "Icon and IP address"
        case .ip: return "IP address"
        case .name: return "Computer name"
        }
    }
}

enum Prefs {
    static var defaults: UserDefaults { .standard }

    static func registerDefaults() {
        var values: [String: Any] = [
            PrefKey.showOnDesktop: true,
            PrefKey.desktopPosition: DesktopPosition.bottomLeft.rawValue,
            PrefKey.desktopScreens: ScreenChoice.main.rawValue,
            PrefKey.marginX: 28.0,
            PrefKey.marginY: 28.0,
            PrefKey.fontFamily: FontChoice.system,
            PrefKey.fontSize: 12.0,
            PrefKey.fontWeight: FontWeightChoice.regular.rawValue,
            PrefKey.textColor: TextColorChoice.light.rawValue,
            PrefKey.customColor: "#FFD60A",
            PrefKey.textOpacity: 0.9,
            PrefKey.textShadow: true,
            PrefKey.showLabels: true,
            PrefKey.showSectionTitles: false,
            PrefKey.interfaceScope: InterfaceScope.active.rawValue,
            PrefKey.volumeScope: VolumeScope.startup.rawValue,
            PrefKey.showLinkLocalIPv6: false,
            PrefKey.showTemporaryIPv6: false,
            PrefKey.showMenuBarIcon: true,
            PrefKey.menuBarStyle: MenuBarStyle.icon.rawValue,
            PrefKey.menuBarSymbol: "info.circle",
            PrefKey.detachablePanel: true,
            PrefKey.showDockIcon: false,
            PrefKey.copyHotKey: HotKeyChoice.ctrlOptCmdC.rawValue,
            PrefKey.panelHotKey: HotKeyChoice.off.rawValue,
            PrefKey.labMode: false,
        ]
        for item in InfoItem.allCases {
            values[PrefKey.item(item)] = item.defaultOn
        }
        defaults.register(defaults: values)
    }

    // MARK: Locking

    static var labMode: Bool { defaults.bool(forKey: PrefKey.labMode) }

    /// True when a setting can't be changed here: lab mode is on, or an MDM profile manages it.
    static func isLocked(_ key: String) -> Bool {
        labMode || defaults.objectIsForced(forKey: key)
    }

    // MARK: Reading

    static func bool(_ key: String) -> Bool { defaults.bool(forKey: key) }
    static func string(_ key: String) -> String { defaults.string(forKey: key) ?? "" }
    static func double(_ key: String) -> Double { defaults.double(forKey: key) }

    static var showOnDesktop: Bool { bool(PrefKey.showOnDesktop) }
    static var showMenuBarIcon: Bool { bool(PrefKey.showMenuBarIcon) }
    static var showDockIcon: Bool { bool(PrefKey.showDockIcon) }
    static var menuBarStyle: MenuBarStyle { MenuBarStyle(rawValue: string(PrefKey.menuBarStyle)) ?? .icon }

    static func displayOptions() -> DisplayOptions {
        let enabled = Set(InfoItem.allCases.filter { bool(PrefKey.item($0)) })
        return DisplayOptions(
            enabled: enabled,
            interfaceScope: InterfaceScope(rawValue: string(PrefKey.interfaceScope)) ?? .active,
            volumeScope: VolumeScope(rawValue: string(PrefKey.volumeScope)) ?? .startup,
            showSectionTitles: bool(PrefKey.showSectionTitles),
            showLinkLocalIPv6: bool(PrefKey.showLinkLocalIPv6),
            showTemporaryIPv6: bool(PrefKey.showTemporaryIPv6)
        )
    }

    static func desktopStyle() -> DesktopStyle {
        let choice = TextColorChoice(rawValue: string(PrefKey.textColor)) ?? .light
        let base: NSColor
        switch choice {
        case .light: base = .white
        case .dark: base = NSColor(white: 0.08, alpha: 1)
        case .custom: base = NSColor.fromHex(string(PrefKey.customColor)) ?? .white
        }
        let size = double(PrefKey.fontSize)
        let marginX = double(PrefKey.marginX)
        let marginY = double(PrefKey.marginY)
        return DesktopStyle(
            fontFamily: string(PrefKey.fontFamily),
            fontSize: CGFloat(min(max(size, 8), 40)),
            fontWeight: string(PrefKey.fontWeight),
            textColor: base,
            opacity: CGFloat(min(max(double(PrefKey.textOpacity), 0.2), 1)),
            shadow: bool(PrefKey.textShadow),
            showLabels: bool(PrefKey.showLabels),
            position: DesktopPosition(rawValue: string(PrefKey.desktopPosition)) ?? .bottomLeft,
            screens: ScreenChoice(rawValue: string(PrefKey.desktopScreens)) ?? .main,
            marginX: CGFloat(max(0, marginX)),
            marginY: CGFloat(max(0, marginY))
        )
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
}
