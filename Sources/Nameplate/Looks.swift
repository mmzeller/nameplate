import Foundation

/// Saved looks: a named set of the desktop appearance settings (fonts, colors, background).
/// Position is not part of a look.
@MainActor
enum Looks {
    static var keys: [String] { Array(Prefs.appearanceDefaults.keys).sorted() }

    /// Built-in starting points. Anything not listed uses the standard value.
    static let builtIn: [(name: String, values: [String: Any])] = [
        ("Classic", [:]),
        ("Frosted Card", [
            PrefKey.background: BackgroundStyle.blur.rawValue,
            PrefKey.backgroundColor: "#000000",
            PrefKey.backgroundOpacity: 0.15,
            PrefKey.backgroundCorner: 14.0,
            PrefKey.backgroundPadding: 14.0,
            PrefKey.textShadow: false,
            PrefKey.textOpacity: 1.0,
        ]),
        ("Terminal", [
            PrefKey.fontFamily: FontChoice.systemMono,
            PrefKey.fontSize: 11.0,
            PrefKey.textColor: TextColorChoice.custom.rawValue,
            PrefKey.customColor: "#3DFF7F",
            PrefKey.labelColor: "#1FA34A",
            PrefKey.headingColor: "#3DFF7F",
            PrefKey.textOpacity: 1.0,
            PrefKey.textShadow: false,
            PrefKey.background: BackgroundStyle.solid.rawValue,
            PrefKey.backgroundColor: "#000000",
            PrefKey.backgroundOpacity: 0.75,
            PrefKey.backgroundCorner: 6.0,
            PrefKey.backgroundPadding: 12.0,
        ]),
        ("Minimal", [
            PrefKey.fontSize: 11.0,
            PrefKey.fontWeight: FontWeightChoice.light.rawValue,
            PrefKey.textOpacity: 0.55,
            PrefKey.showLabels: false,
            PrefKey.showBars: false,
        ]),
        ("Big and Bold", [
            PrefKey.fontSize: 16.0,
            PrefKey.fontWeight: FontWeightChoice.semibold.rawValue,
            PrefKey.textOpacity: 1.0,
            PrefKey.background: BackgroundStyle.solid.rawValue,
            PrefKey.backgroundColor: "#000000",
            PrefKey.backgroundOpacity: 0.35,
            PrefKey.backgroundCorner: 14.0,
            PrefKey.backgroundPadding: 18.0,
            PrefKey.textShadow: false,
        ]),
        ("For Light Wallpapers", [
            PrefKey.textColor: TextColorChoice.dark.rawValue,
            PrefKey.textOpacity: 0.85,
            PrefKey.textShadow: true,
        ]),
    ]

    static var saved: [String: [String: Any]] {
        (Prefs.defaults.dictionary(forKey: PrefKey.savedLooks) as? [String: [String: Any]]) ?? [:]
    }

    static var savedNames: [String] {
        saved.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    static func current() -> [String: Any] {
        var values: [String: Any] = [:]
        for key in keys {
            if let value = Prefs.defaults.object(forKey: key) { values[key] = value }
        }
        return values
    }

    static func apply(_ values: [String: Any]) {
        for key in keys {
            if let value = values[key] {
                Prefs.defaults.set(value, forKey: key)
            } else {
                Prefs.defaults.removeObject(forKey: key)
            }
        }
    }

    static func applyBuiltIn(named name: String) {
        guard let look = builtIn.first(where: { $0.name == name }) else { return }
        apply(look.values)
    }

    static func applySaved(named name: String) {
        guard let values = saved[name] else { return }
        apply(values)
    }

    static func save(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var all = saved
        all[trimmed] = current()
        Prefs.defaults.set(all, forKey: PrefKey.savedLooks)
    }

    static func delete(named name: String) {
        var all = saved
        all[name] = nil
        Prefs.defaults.set(all, forKey: PrefKey.savedLooks)
    }
}
