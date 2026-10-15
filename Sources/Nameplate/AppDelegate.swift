import AppKit
import NameplateCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = InfoStore()
    private let desktop = DesktopController()
    private let monitor = ChangeMonitor()
    private let location = LocationHelper()
    private var status: StatusController!
    private var settings: SettingsWindowController!
    private var timer: Timer?
    private var lastDockSetting: Bool?
    private var lastPublicIPLookup = Date.distantPast

    // MARK: Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.registerDefaults()
        buildMainMenu()

        status = StatusController(store: store)
        settings = SettingsWindowController(location: location)

        store.onUpdate = { [weak self] in self?.render() }
        monitor.onChange = { [weak self] reason in self?.systemChanged(reason) }
        location.onChange = { [weak self] in self?.scheduleRefresh() }
        monitor.start()

        NotificationCenter.default.addObserver(self, selector: #selector(preferencesChanged(_:)),
                                               name: UserDefaults.didChangeNotification, object: nil)
        // Uptime and free space tick along; everything else refreshes the moment it changes.
        let timer = Timer(timeInterval: 60, target: self, selector: #selector(timerFired(_:)), userInfo: nil, repeats: true)
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        applyAdminManagedLoginItem()
        applyPreferences()
        store.refresh()

        if !Prefs.bool(PrefKey.hasLaunched) {
            Prefs.defaults.set(true, forKey: PrefKey.hasLaunched)
            if !Prefs.labMode { showSettings() }
        }
    }

    /// Opening Nameplate again (from Finder, Spotlight or the Dock) shows Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !Prefs.labMode { showSettings() }
        return false
    }

    // MARK: Updating

    private func render() {
        desktop.update(lines: store.lines, style: Prefs.desktopStyle(), enabled: Prefs.showOnDesktop)
        status.updateButton()
    }

    @objc private func timerFired(_ timer: Timer) {
        store.refresh()
        // Re-check the public address every 15 minutes in case it moved without a local network change.
        if Date().timeIntervalSince(lastPublicIPLookup) > 900 {
            lastPublicIPLookup = Date()
            store.refreshPublicIP()
        }
    }

    private func systemChanged(_ reason: ChangeMonitor.Reason) {
        switch reason {
        case .screens:
            desktop.screensChanged()
        case .network, .wake:
            scheduleRefresh()
            schedulePublicIPLookup()
        case .volumes:
            scheduleRefresh()
        }
    }

    /// Network changes arrive in bursts; wait for them to settle.
    func scheduleRefresh() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(performRefresh), object: nil)
        perform(#selector(performRefresh), with: nil, afterDelay: 0.6)
    }

    private func schedulePublicIPLookup() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(performPublicIPLookup), object: nil)
        perform(#selector(performPublicIPLookup), with: nil, afterDelay: 3)
    }

    @objc private func performRefresh() { store.refresh() }

    @objc private func performPublicIPLookup() {
        lastPublicIPLookup = Date()
        store.refreshPublicIP()
    }

    func refreshNow() {
        store.refresh()
    }

    // MARK: Preferences

    @objc private func preferencesChanged(_ note: Notification) {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(applyPreferences), object: nil)
        perform(#selector(applyPreferences), with: nil, afterDelay: 0.05)
    }

    @objc private func applyPreferences() {
        let options = Prefs.displayOptions()
        store.setOptions(options)

        let showDock = Prefs.showDockIcon
        if showDock != lastDockSetting {
            lastDockSetting = showDock
            NSApp.setActivationPolicy(showDock ? .regular : .accessory)
            if NSApp.windows.contains(where: { $0.isVisible && $0.title == "Nameplate Settings" }) {
                NSApp.activate(ignoringOtherApps: true)
            }
        }

        status.apply()

        HotKeyCenter.shared.set(id: 1, to: HotKeyChoice(rawValue: Prefs.string(PrefKey.copyHotKey)) ?? .off) { [weak self] in
            self?.copyAll(feedback: true)
        }
        HotKeyCenter.shared.set(id: 2, to: HotKeyChoice(rawValue: Prefs.string(PrefKey.panelHotKey)) ?? .off) { [weak self] in
            self?.status.showPanelAnywhere()
        }

        if options.has(.interfaces) && options.has(.wifiName) && !Prefs.labMode {
            location.requestIfNeeded()
        }

        render()
    }

    /// An administrator can force launch-at-login on or off with the LaunchAtLogin key.
    private func applyAdminManagedLoginItem() {
        let key = PrefKey.launchAtLogin
        guard Prefs.defaults.objectIsForced(forKey: key) || Prefs.labMode,
              Prefs.defaults.object(forKey: key) != nil else { return }
        LoginItem.set(Prefs.bool(key))
    }

    // MARK: Actions

    func copyAll(feedback: Bool) {
        var options = DisplayOptions.everything
        if store.snapshot.publicIP == nil { options.enabled.remove(.publicIP) }
        let lines = InfoFormatter.lines(for: store.snapshot, options: options)
        copy(InfoFormatter.plainText(lines))
        if feedback { NSSound(named: "Tink")?.play() }
    }

    func copyJSON() {
        copy(InfoFormatter.json(store.snapshot))
    }

    private func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func showSettings() {
        settings.show()
    }

    @objc func copyAllAction(_ sender: Any?) { copyAll(feedback: false) }
    @objc func copyJSONAction(_ sender: Any?) { copyJSON() }
    @objc func copyValueAction(_ sender: NSMenuItem) {
        if let value = sender.representedObject as? String { copy(value) }
    }
    @objc func toggleDesktopAction(_ sender: Any?) {
        Prefs.defaults.set(!Prefs.showOnDesktop, forKey: PrefKey.showOnDesktop)
    }
    @objc func refreshAction(_ sender: Any?) { refreshNow() }
    @objc func installToolAction(_ sender: Any?) { CommandLineTool.install() }
    @objc func settingsAction(_ sender: Any?) { showSettings() }
    @objc func aboutAction(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Nameplate",
            .applicationVersion: NameplateInfo.version,
            .credits: NSAttributedString(string: "Your Mac's details on the desktop, in the menu bar, in Shortcuts and in Terminal."),
        ])
    }

    // MARK: Menu bar (used when the Dock icon is on, and for standard shortcuts in Settings)

    private func buildMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Nameplate", action: #selector(aboutAction(_:)), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(settingsAction(_:)), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Nameplate", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Nameplate", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        let infoItem = NSMenuItem()
        let infoMenu = NSMenu(title: "Info")
        infoMenu.addItem(withTitle: "Copy All Information", action: #selector(copyAllAction(_:)), keyEquivalent: "C").target = self
        infoMenu.addItem(withTitle: "Copy as JSON", action: #selector(copyJSONAction(_:)), keyEquivalent: "").target = self
        infoMenu.addItem(withTitle: "Refresh", action: #selector(refreshAction(_:)), keyEquivalent: "r").target = self
        infoMenu.addItem(.separator())
        infoMenu.addItem(withTitle: "Install Command-Line Tool…", action: #selector(installToolAction(_:)), keyEquivalent: "").target = self
        infoItem.submenu = infoMenu
        main.addItem(infoItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu
    }
}
