import SwiftUI
import AppKit
import NameplateCore

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let location: LocationHelper

    init(location: LocationHelper) {
        self.location = location
    }

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView(location: location))
            let window = NSWindow(contentViewController: host)
            window.title = "Nameplate Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
struct SettingsView: View {
    @ObservedObject var location: LocationHelper

    var body: some View {
        VStack(spacing: 0) {
            if Prefs.labMode {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                    Text("Lab mode is on, so settings are locked. An administrator can turn it off with:\nsudo defaults delete /Library/Preferences/\(NameplateInfo.bundleIdentifier) LabMode")
                        .font(.callout)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(Color.orange.opacity(0.15))
            }
            TabView {
                InformationTab(location: location)
                    .tabItem { Label("Information", systemImage: "list.bullet.rectangle") }
                DesktopTab()
                    .tabItem { Label("Desktop", systemImage: "menubar.dock.rectangle") }
                MenuBarTab()
                    .tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }
                GeneralTab()
                    .tabItem { Label("General", systemImage: "gearshape") }
            }
            .disabled(Prefs.labMode)
            .padding(.top, 6)
        }
        .frame(width: 580, height: 640)
    }
}

private extension View {
    /// Greys out a control when an administrator manages that setting.
    func locked(_ key: String) -> some View {
        disabled(Prefs.isLocked(key))
    }
}

// MARK: - Information

@MainActor
private struct ItemToggle: View {
    let item: InfoItem
    @AppStorage private var isOn: Bool

    init(_ item: InfoItem) {
        self.item = item
        _isOn = AppStorage(wrappedValue: item.defaultOn, PrefKey.item(item))
    }

    var body: some View {
        Toggle(item.title, isOn: $isOn)
            .locked(PrefKey.item(item))
    }
}

@MainActor
private struct InformationTab: View {
    @ObservedObject var location: LocationHelper
    @AppStorage(PrefKey.interfaceScope) private var interfaceScope = InterfaceScope.active.rawValue
    @AppStorage(PrefKey.volumeScope) private var volumeScope = VolumeScope.startup.rawValue
    @AppStorage(PrefKey.showLinkLocalIPv6) private var showLinkLocal = false
    @AppStorage(PrefKey.showTemporaryIPv6) private var showTemporary = false
    @AppStorage(PrefKey.item(.interfaces)) private var showInterfaces = true
    @AppStorage(PrefKey.item(.wifiName)) private var showWiFiName = true

    var body: some View {
        Form {
            Section("Hardware") {
                ForEach(InfoItem.items(in: .hardware), id: \.self) { ItemToggle($0) }
            }
            Section("Status") {
                ForEach(InfoItem.items(in: .status), id: \.self) { ItemToggle($0) }
                Picker("Disks to show", selection: $volumeScope) {
                    ForEach(VolumeScope.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                }
                .locked(PrefKey.volumeScope)
            }
            Section("Network") {
                ItemToggle(.interfaces)
                Group {
                    Picker("Interfaces to show", selection: $interfaceScope) {
                        ForEach(InterfaceScope.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                    }
                    .locked(PrefKey.interfaceScope)
                    ForEach(InfoItem.items(in: .network).filter(\.dependsOnInterfaces), id: \.self) { ItemToggle($0) }
                    Toggle("Include link-local IPv6 addresses (fe80::)", isOn: $showLinkLocal)
                        .locked(PrefKey.showLinkLocalIPv6)
                    Toggle("Include temporary (privacy) IPv6 addresses", isOn: $showTemporary)
                        .locked(PrefKey.showTemporaryIPv6)
                }
                .disabled(!showInterfaces)

                if showInterfaces && showWiFiName && !location.isAllowed {
                    HStack(alignment: .firstTextBaseline) {
                        Text("macOS only shares the Wi-Fi name with apps allowed to use Location Services. Nameplate never reads your location. Status: \(location.statusText)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if location.status == .notDetermined {
                            Button("Allow…") { location.requestIfNeeded() }
                        } else {
                            Button("Open Settings") {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }
                    }
                }

                ItemToggle(.publicIP)
                Text("The public IP is looked up at \(PublicIP.serviceHost). That is the only time Nameplate contacts the internet, and only while this is on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Desktop

@MainActor
private struct DesktopTab: View {
    @AppStorage(PrefKey.showOnDesktop) private var showOnDesktop = true
    @AppStorage(PrefKey.desktopPosition) private var position = DesktopPosition.bottomLeft.rawValue
    @AppStorage(PrefKey.desktopScreens) private var screens = ScreenChoice.main.rawValue
    @AppStorage(PrefKey.marginX) private var marginX = 28.0
    @AppStorage(PrefKey.marginY) private var marginY = 28.0
    @AppStorage(PrefKey.fontFamily) private var fontFamily = FontChoice.system
    @AppStorage(PrefKey.fontSize) private var fontSize = 12.0
    @AppStorage(PrefKey.fontWeight) private var fontWeight = FontWeightChoice.regular.rawValue
    @AppStorage(PrefKey.textColor) private var textColor = TextColorChoice.light.rawValue
    @AppStorage(PrefKey.customColor) private var customColor = "#FFD60A"
    @AppStorage(PrefKey.textOpacity) private var opacity = 0.9
    @AppStorage(PrefKey.textShadow) private var shadow = true
    @AppStorage(PrefKey.showLabels) private var showLabels = true
    @AppStorage(PrefKey.showSectionTitles) private var showSectionTitles = false
    @State private var families: [String] = NSFontManager.shared.availableFontFamilies.sorted()

    var body: some View {
        Form {
            Section {
                Toggle("Show information on the desktop", isOn: $showOnDesktop)
                    .locked(PrefKey.showOnDesktop)
            } footer: {
                Text("It sits on top of your wallpaper and under your desktop icons and windows. Your wallpaper isn't changed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Placement") {
                Picker("Position", selection: $position) {
                    ForEach(DesktopPosition.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                }
                .locked(PrefKey.desktopPosition)
                Picker("Show on", selection: $screens) {
                    ForEach(ScreenChoice.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                }
                .locked(PrefKey.desktopScreens)
                LabeledContent("Side margin") {
                    HStack {
                        Slider(value: $marginX, in: 0...400)
                        Text("\(Int(marginX)) pt").monospacedDigit().frame(width: 52, alignment: .trailing)
                    }
                }
                .locked(PrefKey.marginX)
                LabeledContent("Top / bottom margin") {
                    HStack {
                        Slider(value: $marginY, in: 0...400)
                        Text("\(Int(marginY)) pt").monospacedDigit().frame(width: 52, alignment: .trailing)
                    }
                }
                .locked(PrefKey.marginY)
            }
            .disabled(!showOnDesktop)

            Section("Text") {
                Picker("Font", selection: $fontFamily) {
                    ForEach(FontChoice.builtIn, id: \.self) { Text($0).tag($0) }
                    Divider()
                    ForEach(families, id: \.self) { Text($0).tag($0) }
                }
                .locked(PrefKey.fontFamily)
                Picker("Weight", selection: $fontWeight) {
                    ForEach(FontWeightChoice.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                }
                .locked(PrefKey.fontWeight)
                LabeledContent("Size") {
                    HStack {
                        Slider(value: $fontSize, in: 9...28, step: 1)
                        Text("\(Int(fontSize)) pt").monospacedDigit().frame(width: 52, alignment: .trailing)
                    }
                }
                .locked(PrefKey.fontSize)
                Picker("Color", selection: $textColor) {
                    ForEach(TextColorChoice.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .locked(PrefKey.textColor)
                if textColor == TextColorChoice.custom.rawValue {
                    ColorPicker("Custom color", selection: colorBinding, supportsOpacity: false)
                        .locked(PrefKey.customColor)
                }
                LabeledContent("Opacity") {
                    HStack {
                        Slider(value: $opacity, in: 0.2...1)
                        Text("\(Int((opacity * 100).rounded()))%").monospacedDigit().frame(width: 52, alignment: .trailing)
                    }
                }
                .locked(PrefKey.textOpacity)
                Toggle("Soft shadow behind text (easier to read on busy wallpapers)", isOn: $shadow)
                    .locked(PrefKey.textShadow)
                Toggle("Show labels", isOn: $showLabels)
                    .locked(PrefKey.showLabels)
                Toggle("Show section titles (Hardware, Status, Network)", isOn: $showSectionTitles)
                    .locked(PrefKey.showSectionTitles)
            }
            .disabled(!showOnDesktop)
        }
        .formStyle(.grouped)
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: NSColor.fromHex(customColor) ?? .white) },
            set: { customColor = NSColor($0).hexString }
        )
    }
}

// MARK: - Menu bar

@MainActor
private struct MenuBarTab: View {
    @AppStorage(PrefKey.showMenuBarIcon) private var showIcon = true
    @AppStorage(PrefKey.menuBarStyle) private var style = MenuBarStyle.icon.rawValue
    @AppStorage(PrefKey.menuBarSymbol) private var symbol = "info.circle"
    @AppStorage(PrefKey.detachablePanel) private var detachable = true

    private let symbols = [
        "info.circle", "info.square", "desktopcomputer", "laptopcomputer", "macmini",
        "display", "network", "cpu", "tag", "person.text.rectangle",
    ]

    var body: some View {
        Form {
            Section {
                Toggle("Show Nameplate in the menu bar", isOn: $showIcon)
                    .locked(PrefKey.showMenuBarIcon)
            } footer: {
                Text("Click it for the info panel. Right-click or Control-click it for the menu. If you hide it along with the desktop text and Dock icon, open Nameplate again from Applications to get back to Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Picker("Shows", selection: $style) {
                    ForEach(MenuBarStyle.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                }
                .locked(PrefKey.menuBarStyle)
                Picker("Icon", selection: $symbol) {
                    ForEach(symbols, id: \.self) { name in
                        Label(name, systemImage: name).tag(name)
                    }
                }
                .locked(PrefKey.menuBarSymbol)
                Toggle("Panel can be dragged away to stay open", isOn: $detachable)
                    .locked(PrefKey.detachablePanel)
            }
            .disabled(!showIcon)
        }
        .formStyle(.grouped)
    }
}

// MARK: - General

@MainActor
private struct GeneralTab: View {
    @AppStorage(PrefKey.showDockIcon) private var showDockIcon = false
    @AppStorage(PrefKey.copyHotKey) private var copyHotKey = HotKeyChoice.ctrlOptCmdC.rawValue
    @AppStorage(PrefKey.panelHotKey) private var panelHotKey = HotKeyChoice.off.rawValue
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var toolInstalled = CommandLineTool.isInstalled

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { newValue in
                        LoginItem.set(newValue)
                        launchAtLogin = LoginItem.isEnabled
                    }
                ))
                .locked(PrefKey.launchAtLogin)
                Toggle("Show Dock icon", isOn: $showDockIcon)
                    .locked(PrefKey.showDockIcon)
            }

            Section("Keyboard shortcuts") {
                Picker("Copy all information", selection: $copyHotKey) {
                    ForEach(HotKeyChoice.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                }
                .locked(PrefKey.copyHotKey)
                Picker("Open the info panel", selection: $panelHotKey) {
                    ForEach(HotKeyChoice.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                }
                .locked(PrefKey.panelHotKey)
            }

            Section {
                LabeledContent("Command-line tool") {
                    if toolInstalled {
                        Text("Installed as nameplate").foregroundStyle(.secondary)
                    } else {
                        Button("Install…") {
                            CommandLineTool.install()
                            toolInstalled = CommandLineTool.isInstalled
                        }
                    }
                }
            } header: {
                Text("Command line and Shortcuts")
            } footer: {
                Text("In the Shortcuts app, add a “Run Shell Script” action with  /usr/local/bin/nameplate --get ip  (or serial, model, ssid, --json …). Run  nameplate --keys  in Terminal to see every value.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Section("Lab mode") {
                Text("For shared Macs in labs and offices. Lab mode locks these settings and removes the right-click menu (including Quit). Set it for everyone with:\nsudo defaults write /Library/Preferences/\(NameplateInfo.bundleIdentifier) LabMode -bool true\nAny setting can also be pushed and locked with a configuration profile — see the README.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Section {
                LabeledContent("Version", value: NameplateInfo.version)
            }
        }
        .formStyle(.grouped)
    }
}
