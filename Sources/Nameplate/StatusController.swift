import AppKit
import SwiftUI
import NameplateCore

/// The menu bar icon: click for the info panel, right-click (or Control-click) for a menu.
@MainActor
final class StatusController: NSObject, NSPopoverDelegate {
    private var item: NSStatusItem?
    private let popover = NSPopover()
    private let store: InfoStore

    init(store: InfoStore) {
        self.store = store
        super.init()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let host = NSHostingController(rootView: InfoPanelView(store: store))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
    }

    // MARK: Showing the icon

    func apply() {
        guard Prefs.showMenuBarIcon else {
            if let item {
                NSStatusBar.system.removeStatusItem(item)
                self.item = nil
            }
            popover.performClose(nil)
            return
        }
        if item == nil {
            let newItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            newItem.autosaveName = "NameplateStatusItem"
            if let button = newItem.button {
                button.target = self
                button.action = #selector(buttonClicked(_:))
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            }
            // Hidden from Settings rather than by Command-dragging, so it can always come back.
            newItem.behavior = []
            if !newItem.isVisible { newItem.isVisible = true }
            item = newItem
        }
        updateButton()
    }

    func updateButton() {
        guard let button = item?.button else { return }
        let style = Prefs.menuBarStyle
        let snapshot = store.snapshot
        let ip = snapshot.network.primary?.ipv4.first?.address ?? "No network"

        var image: NSImage?
        if style == .icon || style == .iconAndIP {
            let name = Prefs.string(PrefKey.menuBarSymbol)
            image = NSImage(systemSymbolName: name.isEmpty ? "info.circle" : name, accessibilityDescription: "Nameplate")
                ?? NSImage(systemSymbolName: "info.circle", accessibilityDescription: "Nameplate")
            image = image?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .regular))
            image?.isTemplate = true
        }
        button.image = image
        button.imagePosition = .imageLeading

        let title: String
        switch style {
        case .icon: title = ""
        case .iconAndIP: title = " " + ip
        case .ip: title = ip
        case .name: title = snapshot.computerName
        }
        if title.isEmpty {
            button.title = ""
        } else {
            button.attributedTitle = NSAttributedString(string: title, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
            ])
        }
        button.toolTip = "\(snapshot.computerName) — \(ip)"
    }

    // MARK: Clicks

    @objc private func buttonClicked(_ sender: Any?) {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if wantsMenu {
            showMenu()
        } else {
            togglePanel()
        }
    }

    func togglePanel() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = item?.button else { return }
        (NSApp.delegate as? AppDelegate)?.refreshNow()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    /// Opens the panel even if the menu bar icon is hidden (used by the keyboard shortcut).
    func showPanelAnywhere() {
        if item?.button != nil {
            if !popover.isShown { togglePanel() }
        } else {
            (NSApp.delegate as? AppDelegate)?.showSettings()
        }
    }

    nonisolated func popoverShouldDetach(_ popover: NSPopover) -> Bool {
        UserDefaults.standard.bool(forKey: PrefKey.detachablePanel)
    }

    // MARK: Menu

    private func showMenu() {
        guard let item, let app = NSApp.delegate as? AppDelegate else { return }
        let menu = NSMenu()
        let snapshot = store.snapshot

        let title = NSMenuItem(title: snapshot.computerName, action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        menu.addItem(withTitle: "Copy All Information", action: #selector(AppDelegate.copyAllAction(_:)), keyEquivalent: "c").target = app
        menu.addItem(withTitle: "Copy as JSON", action: #selector(AppDelegate.copyJSONAction(_:)), keyEquivalent: "").target = app

        let copyItem = NSMenuItem(title: "Copy", action: nil, keyEquivalent: "")
        let copyMenu = NSMenu()
        for value in InfoFormatter.values(for: snapshot) where !value.key.contains(".") {
            let shown = value.value.count > 48 ? String(value.value.prefix(47)) + "…" : value.value
            let entry = NSMenuItem(title: "\(value.label): \(shown)", action: #selector(AppDelegate.copyValueAction(_:)), keyEquivalent: "")
            entry.representedObject = value.value
            entry.target = app
            copyMenu.addItem(entry)
        }
        copyItem.submenu = copyMenu
        menu.addItem(copyItem)
        menu.addItem(.separator())

        let desktop = NSMenuItem(title: "Show on Desktop", action: #selector(AppDelegate.toggleDesktopAction(_:)), keyEquivalent: "")
        desktop.state = Prefs.showOnDesktop ? .on : .off
        desktop.target = app
        menu.addItem(desktop)
        menu.addItem(withTitle: "Refresh", action: #selector(AppDelegate.refreshAction(_:)), keyEquivalent: "r").target = app
        menu.addItem(.separator())

        if !CommandLineTool.isInstalled {
            menu.addItem(withTitle: "Install Command-Line Tool…", action: #selector(AppDelegate.installToolAction(_:)), keyEquivalent: "").target = app
        }
        menu.addItem(withTitle: "Settings…", action: #selector(AppDelegate.settingsAction(_:)), keyEquivalent: ",").target = app
        menu.addItem(withTitle: "About Nameplate", action: #selector(AppDelegate.aboutAction(_:)), keyEquivalent: "").target = app
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Nameplate", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // Attach the menu just long enough for this click, so a left click still opens the panel.
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }
}
