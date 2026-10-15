import AppKit

@main
enum NameplateApp {
    @MainActor
    static func main() {
        Prefs.registerDefaults()
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
