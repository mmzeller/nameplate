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
        TabView {
            LayoutTab()
                .tabItem { Label("Layout", systemImage: "list.bullet.rectangle") }
            AppearanceTab()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            MenuBarTab()
                .tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }
            ShortcutsTab()
                .tabItem { Label("Shortcuts", systemImage: "command") }
            GeneralTab(location: location)
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .padding(.top, 6)
        .frame(width: 700, height: 700)
    }
}

@MainActor
private var app: AppDelegate? { NSApp.delegate as? AppDelegate }

// MARK: - Insert menu for {placeholders}

@MainActor
private struct InsertMenu: View {
    var insert: (String) -> Void

    var body: some View {
        Menu {
            ForEach(InfoFormatter.templateKeys, id: \.name) { group in
                Section(group.name) {
                    ForEach(group.keys, id: \.key) { entry in
                        Button("\(entry.title)   {\(entry.key)}") { insert("{\(entry.key)}") }
                    }
                }
            }
        } label: {
            Image(systemName: "curlybraces")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Insert a value that fills in by itself")
    }
}

// MARK: - Layout

@MainActor
private struct LayoutTab: View {
    @State private var layout = Prefs.layout()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Lines on the desktop and in the menu bar panel")
                .font(.headline)
            Text("Drag to reorder. Untick to hide. Type in the label box to rename a line (a single space hides its label). Text lines and headings can include values in braces, like {ip} or {uptime}; use the { } menu to pick one.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List {
                ForEach($layout.entries) { $entry in
                    EntryRow(entry: $entry) {
                        layout.entries.removeAll { $0.id == entry.id }
                    }
                }
                .onMove { layout.entries.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(minHeight: 280)

            HStack {
                Menu("Add") {
                    Button("Text Line") { add(LayoutEntry(kind: .text, text: "")) }
                    Button("Heading") { add(.heading("Heading")) }
                    Button("Blank Line") { add(.spacer()) }
                    Button("Command Output") { add(LayoutEntry(kind: .command, text: "", interval: 60)) }
                    if !missingItems.isEmpty {
                        Divider()
                        ForEach(missingItems, id: \.self) { item in
                            Button(item.title) { add(.builtIn(item)) }
                        }
                    }
                }
                .fixedSize()
                Spacer()
                Button("Reset to Standard") {
                    layout = .standard()
                }
            }

            Text("Each network interface shows")
                .font(.headline)
                .padding(.top, 6)
            List {
                ForEach($layout.interfaceDetails) { $entry in
                    EntryRow(entry: $entry) {
                        layout.interfaceDetails.removeAll { $0.id == entry.id }
                    }
                }
                .onMove { layout.interfaceDetails.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(height: 170)
            if !missingDetails.isEmpty {
                Menu("Add") {
                    ForEach(missingDetails, id: \.self) { item in
                        Button(item.title) { layout.interfaceDetails.append(.builtIn(item)) }
                    }
                }
                .fixedSize()
            }
        }
        .padding(20)
        .onChange(of: layout) { newValue in
            Prefs.saveLayout(newValue)
        }
    }

    private var missingItems: [InfoItem] {
        Layout.topLevelItems.filter { item in !layout.entries.contains { $0.item == item } }
    }

    private var missingDetails: [InfoItem] {
        Layout.detailItems.filter { item in !layout.interfaceDetails.contains { $0.item == item } }
    }

    private func add(_ entry: LayoutEntry) {
        layout.entries.append(entry)
    }
}

@MainActor
private struct EntryRow: View {
    @Binding var entry: LayoutEntry
    var onDelete: () -> Void

    private static let intervals = [5, 15, 30, 60, 300, 900, 3600]

    private static func intervalTitle(_ seconds: Int) -> String {
        switch seconds {
        case ..<60: return "every \(seconds) sec"
        case 3600: return "every hour"
        case 60: return "every minute"
        default: return "every \(seconds / 60) min"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .help("Drag to reorder")
            Toggle("", isOn: $entry.enabled)
                .labelsHidden()
                .toggleStyle(.checkbox)

            switch entry.kind {
            case .item:
                Text(entry.title)
                    .frame(width: 210, alignment: .leading)
                    .foregroundStyle(entry.enabled ? .primary : .secondary)
                if entry.item != .interfaces {
                    TextField(entry.item?.defaultLabel ?? "Label", text: labelBinding)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                        .help("Label shown next to the value. Leave empty for the standard label; type a space for none.")
                } else {
                    Text("one block per network interface")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            case .text:
                TextField("Label", text: labelBinding)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                TextField("Your text, e.g. Owner: Matthew, or {ip}", text: $entry.text)
                    .textFieldStyle(.roundedBorder)
                InsertMenu { entry.text += $0 }
            case .heading:
                Text("Heading")
                    .foregroundStyle(.secondary)
                    .frame(width: 100, alignment: .leading)
                TextField("Title", text: $entry.text)
                    .textFieldStyle(.roundedBorder)
                InsertMenu { entry.text += $0 }
            case .spacer:
                Text("Blank line")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            case .command:
                TextField("Label", text: labelBinding)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                TextField("Shell command, e.g. curl -s wttr.in/?format=3", text: $entry.text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                Picker("", selection: $entry.interval) {
                    ForEach(EntryRow.intervals, id: \.self) { seconds in
                        Text(EntryRow.intervalTitle(seconds)).tag(seconds)
                    }
                }
                .labelsHidden()
                .frame(width: 120)
            }

            Button(action: onDelete) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Remove this line")
        }
        .padding(.vertical, 2)
    }

    private var labelBinding: Binding<String> {
        Binding(
            get: { entry.label ?? "" },
            set: { entry.label = $0.isEmpty ? nil : $0 }
        )
    }
}

// MARK: - Appearance

@MainActor
private struct AppearanceTab: View {
    @AppStorage(PrefKey.showOnDesktop) private var showOnDesktop = true
    @AppStorage(PrefKey.desktopScreens) private var screens = ScreenSelection.menuBarDisplay.rawValue
    @AppStorage(PrefKey.fontFamily) private var fontFamily = FontChoice.system
    @AppStorage(PrefKey.fontSize) private var fontSize = 12.0
    @AppStorage(PrefKey.fontWeight) private var fontWeight = FontWeightChoice.regular.rawValue
    @AppStorage(PrefKey.lineSpacing) private var lineSpacing = 1.0
    @AppStorage(PrefKey.textColor) private var textColor = TextColorChoice.light.rawValue
    @AppStorage(PrefKey.customColor) private var customColor = "#FFD60A"
    @AppStorage(PrefKey.labelColor) private var labelColor = ""
    @AppStorage(PrefKey.headingColor) private var headingColor = ""
    @AppStorage(PrefKey.textOpacity) private var opacity = 0.9
    @AppStorage(PrefKey.textShadow) private var shadow = true
    @AppStorage(PrefKey.showLabels) private var showLabels = true
    @AppStorage(PrefKey.showBars) private var showBars = true
    @AppStorage(PrefKey.background) private var background = BackgroundStyle.off.rawValue
    @AppStorage(PrefKey.backgroundColor) private var backgroundColor = "#000000"
    @AppStorage(PrefKey.backgroundOpacity) private var backgroundOpacity = 0.35
    @AppStorage(PrefKey.backgroundCorner) private var backgroundCorner = 12.0
    @AppStorage(PrefKey.backgroundPadding) private var backgroundPadding = 14.0

    @State private var families: [String] = []
    @State private var savedNames: [String] = []
    @State private var naming = false
    @State private var newName = ""
    @State private var displays: [Displays.Info] = []
    @State private var adjustKey = ""
    /// Bumped whenever settings change, so per-display positions shown here stay current.
    @State private var revision = 0

    var body: some View {
        let _ = revision
        Form {
            Section {
                HStack {
                    Menu("Apply a Look") {
                        Section("Built in") {
                            ForEach(Looks.builtIn.map { $0.name }, id: \.self) { name in
                                Button(name) { Looks.applyBuiltIn(named: name) }
                            }
                        }
                        if !savedNames.isEmpty {
                            Section("Saved") {
                                ForEach(savedNames, id: \.self) { name in
                                    Button(name) { Looks.applySaved(named: name) }
                                }
                            }
                        }
                    }
                    .fixedSize()
                    Button("Save Current Look…") {
                        newName = ""
                        naming = true
                    }
                    if !savedNames.isEmpty {
                        Menu("Delete") {
                            ForEach(savedNames, id: \.self) { name in
                                Button(name) {
                                    Looks.delete(named: name)
                                    savedNames = Looks.savedNames
                                }
                            }
                        }
                        .fixedSize()
                    }
                }
            } header: {
                Text("Looks")
            } footer: {
                Text("A look saves the fonts, colors and background below, so you can switch between styles. Position isn't part of a look.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Show information on the desktop", isOn: $showOnDesktop)
            } footer: {
                Text("It sits on top of your wallpaper and under your desktop icons and windows. Your wallpaper isn't changed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Show on", selection: $screens) {
                    Text("Display with the menu bar").tag(ScreenSelection.menuBarDisplay.rawValue)
                    Text("Every display").tag(ScreenSelection.every.rawValue)
                    Divider()
                    ForEach(displayChoices, id: \.tag) { choice in
                        Text(choice.title).tag(choice.tag)
                    }
                }
                if ScreenSelection(screens) == .every && displays.count > 1 {
                    Picker("Adjust position on", selection: $adjustKey) {
                        ForEach(displays) { display in
                            Text(display.name).tag(display.key)
                        }
                    }
                }
                HStack {
                    Button("Move on Screen…") { app?.beginMoveDesktop() }
                    Text("Drag it anywhere; it stays put relative to the nearest corner.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let target = adjustTarget {
                    Picker("Corner", selection: cornerBinding(target.key)) {
                        ForEach(DesktopPosition.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                    }
                    slider("Side margin", value: offsetBinding(target.key, \.x),
                           range: 0...Double(max(100, target.screen.visibleFrame.width - 60)), step: 1, unit: "pt")
                    slider("Top / bottom margin", value: offsetBinding(target.key, \.y),
                           range: 0...Double(max(100, target.screen.visibleFrame.height - 40)), step: 1, unit: "pt")
                    HStack {
                        Text(Prefs.hasOwnPlacement(target.key)
                             ? "Position saved for \(target.name)."
                             : "\(target.name) uses the standard position.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if Prefs.hasOwnPlacement(target.key) {
                            Button("Reset Position") { Prefs.removePlacement(forDisplay: target.key) }
                        }
                    }
                }
            } header: {
                Text("Placement")
            } footer: {
                Text("Each display keeps its own position, and the info always stays fully on screen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!showOnDesktop)

            Section("Text") {
                Picker("Font", selection: $fontFamily) {
                    ForEach(FontChoice.builtIn, id: \.self) { Text($0).tag($0) }
                    Divider()
                    ForEach(families, id: \.self) { Text($0).tag($0) }
                }
                Picker("Weight", selection: $fontWeight) {
                    ForEach(FontWeightChoice.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                }
                slider("Size", value: $fontSize, range: 9...32, step: 1, unit: "pt")
                LabeledContent("Line spacing") {
                    HStack {
                        Slider(value: $lineSpacing, in: 0...3)
                        Text(String(format: "%.1f×", lineSpacing))
                            .monospacedDigit()
                            .frame(width: 60, alignment: .trailing)
                    }
                }
                Picker("Color", selection: $textColor) {
                    ForEach(TextColorChoice.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                if textColor == TextColorChoice.custom.rawValue {
                    ColorPicker("Text color", selection: hexBinding($customColor, fallback: .white), supportsOpacity: false)
                }
                optionalColor("Own color for labels", hex: $labelColor, suggestion: "#9AA4B2")
                optionalColor("Own color for headings", hex: $headingColor, suggestion: "#FFD60A")
                slider("Opacity", value: $opacity, range: 0.2...1, percent: true)
                Toggle("Soft shadow behind text (easier to read on busy wallpapers)", isOn: $shadow)
                Toggle("Show labels", isOn: $showLabels)
                Toggle("Show usage bars for disk, CPU, memory and battery", isOn: $showBars)
            }
            .disabled(!showOnDesktop)

            Section("Background") {
                Picker("Background", selection: $background) {
                    ForEach(BackgroundStyle.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                if background != BackgroundStyle.off.rawValue {
                    ColorPicker(background == BackgroundStyle.blur.rawValue ? "Tint" : "Color",
                                selection: hexBinding($backgroundColor, fallback: .black), supportsOpacity: false)
                    slider(background == BackgroundStyle.blur.rawValue ? "Tint strength" : "Opacity",
                           value: $backgroundOpacity, range: 0...1, percent: true)
                    slider("Corner rounding", value: $backgroundCorner, range: 0...40, step: 1, unit: "pt")
                    slider("Padding", value: $backgroundPadding, range: 0...48, step: 1, unit: "pt")
                }
            }
            .disabled(!showOnDesktop)
        }
        .formStyle(.grouped)
        .onAppear {
            if families.isEmpty { families = NSFontManager.shared.availableFontFamilies.sorted() }
            savedNames = Looks.savedNames
            displays = Displays.all()
            if !displays.contains(where: { $0.key == adjustKey }) { adjustKey = displays.first?.key ?? "" }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            displays = Displays.all()
            if !displays.contains(where: { $0.key == adjustKey }) { adjustKey = displays.first?.key ?? "" }
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            revision &+= 1
        }
        .alert("Save Look", isPresented: $naming) {
            TextField("Name", text: $newName)
            Button("Save") {
                Looks.save(named: newName)
                savedNames = Looks.savedNames
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saving with the name of an existing look replaces it.")
        }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double? = nil,
                        unit: String = "", percent: Bool = false) -> some View {
        LabeledContent(title) {
            HStack {
                if let step {
                    Slider(value: value, in: range, step: step)
                } else {
                    Slider(value: value, in: range)
                }
                Text(percent ? "\(Int((value.wrappedValue * 100).rounded()))%" : "\(Int(value.wrappedValue.rounded())) \(unit)")
                    .monospacedDigit()
                    .frame(width: 60, alignment: .trailing)
            }
        }
    }

    // MARK: Placement helpers

    private struct DisplayChoice {
        let tag: String
        let title: String
    }

    /// Each connected display, plus the chosen one if it's unplugged right now.
    private var displayChoices: [DisplayChoice] {
        var choices = displays.map { display in
            DisplayChoice(tag: ScreenSelection.display(display.key).rawValue,
                          title: display.hasMenuBar ? "\(display.name) only (has the menu bar)" : "\(display.name) only")
        }
        if case .display(let key) = ScreenSelection(screens), !displays.contains(where: { $0.key == key }) {
            let name = Prefs.displayName(key) ?? "Display"
            choices.append(DisplayChoice(tag: screens, title: "\(name) only (not connected)"))
        }
        return choices
    }

    /// The display whose position the controls below are changing.
    private var adjustTarget: Displays.Info? {
        switch ScreenSelection(screens) {
        case .menuBarDisplay:
            return displays.first
        case .display(let key):
            return displays.first { $0.key == key } ?? displays.first
        case .every:
            return displays.first { $0.key == adjustKey } ?? displays.first
        }
    }

    private func cornerBinding(_ key: String) -> Binding<String> {
        Binding(
            get: { Prefs.placement(forDisplay: key).corner.rawValue },
            set: { raw in
                var placement = Prefs.placement(forDisplay: key)
                placement.corner = DesktopPosition(rawValue: raw) ?? placement.corner
                Prefs.setPlacement(placement, forDisplay: key)
            }
        )
    }

    private func offsetBinding(_ key: String, _ path: WritableKeyPath<Placement, CGFloat>) -> Binding<Double> {
        Binding(
            get: { Double(Prefs.placement(forDisplay: key)[keyPath: path]) },
            set: { value in
                var placement = Prefs.placement(forDisplay: key)
                placement[keyPath: path] = CGFloat(value.rounded())
                Prefs.setPlacement(placement, forDisplay: key)
            }
        )
    }

    private func optionalColor(_ title: String, hex: Binding<String>, suggestion: String) -> some View {
        HStack {
            Toggle(title, isOn: Binding(
                get: { !hex.wrappedValue.isEmpty },
                set: { hex.wrappedValue = $0 ? suggestion : "" }
            ))
            Spacer()
            if !hex.wrappedValue.isEmpty {
                ColorPicker("", selection: hexBinding(hex, fallback: .white), supportsOpacity: false)
                    .labelsHidden()
            }
        }
    }

    private func hexBinding(_ hex: Binding<String>, fallback: NSColor) -> Binding<Color> {
        Binding(
            get: { Color(nsColor: NSColor.fromHex(hex.wrappedValue) ?? fallback) },
            set: { hex.wrappedValue = NSColor($0).hexString }
        )
    }
}

// MARK: - Menu bar

@MainActor
private struct MenuBarTab: View {
    @AppStorage(PrefKey.showMenuBarIcon) private var showInMenuBar = true
    @AppStorage(PrefKey.menuBarShowSymbol) private var showSymbol = true
    @AppStorage(PrefKey.menuBarSymbol) private var symbol = "info.circle"
    @AppStorage(PrefKey.menuBarText) private var text = MenuBarText.off.rawValue
    @AppStorage(PrefKey.menuBarTemplate) private var template = "{ip}"
    @AppStorage(PrefKey.detachablePanel) private var detachable = true

    private let symbols = [
        "info.circle", "info.square", "desktopcomputer", "laptopcomputer", "macmini",
        "display", "network", "wifi", "cpu", "memorychip", "internaldrive", "gauge.medium", "tag", "person.text.rectangle",
    ]

    var body: some View {
        Form {
            Section {
                Toggle("Show Nameplate in the menu bar", isOn: $showInMenuBar)
            } footer: {
                Text("Click it for the info panel. Right-click or Control-click it for the menu. If you hide it, open Nameplate again from Applications to get back to Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("What it shows") {
                Toggle("Icon", isOn: $showSymbol)
                Picker("Icon style", selection: $symbol) {
                    ForEach(symbols, id: \.self) { name in
                        Label(name, systemImage: name).tag(name)
                    }
                }
                .disabled(!showSymbol)
                Picker("Text", selection: $text) {
                    ForEach(MenuBarText.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                }
                if text == MenuBarText.custom.rawValue {
                    HStack {
                        TextField("e.g. {ip} · {cpu}", text: $template)
                            .textFieldStyle(.roundedBorder)
                        InsertMenu { template += $0 }
                    }
                    Text("Mix your own words with values in braces, e.g. “{ip} · up {uptime-short}” or “CPU {cpu}  ↓{down}”. Live values update every couple of seconds.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!showInMenuBar)
            Section {
                Toggle("Panel can be dragged away to stay open", isOn: $detachable)
            }
            .disabled(!showInMenuBar)
        }
        .formStyle(.grouped)
    }
}

// MARK: - Shortcuts

@MainActor
private struct ShortcutsTab: View {
    @AppStorage(PrefKey.copyHotKey) private var copyAll = HotKeySpec.defaultCopy.stringValue
    @AppStorage(PrefKey.panelHotKey) private var panel = "none"
    @AppStorage(PrefKey.toggleDesktopHotKey) private var toggleDesktop = "none"
    @AppStorage(PrefKey.copyIPHotKey) private var copyIP = "none"

    var body: some View {
        Form {
            Section {
                LabeledContent("Copy all information") { ShortcutRecorder(value: $copyAll) }
                LabeledContent("Copy IP address") { ShortcutRecorder(value: $copyIP) }
                LabeledContent("Open the info panel") { ShortcutRecorder(value: $panel) }
                LabeledContent("Show or hide the desktop info") { ShortcutRecorder(value: $toggleDesktop) }
            } footer: {
                Text("Click a button, then press the keys. Use at least one of ⌘, ⌥ or ⌃ (F-keys work alone). Escape cancels; Delete removes the shortcut. These work from any app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - General

@MainActor
private struct GeneralTab: View {
    @ObservedObject var location: LocationHelper
    @AppStorage(PrefKey.showDockIcon) private var showDockIcon = false
    @AppStorage(PrefKey.interfaceScope) private var interfaceScope = InterfaceScope.active.rawValue
    @AppStorage(PrefKey.volumeScope) private var volumeScope = VolumeScope.startup.rawValue
    @AppStorage(PrefKey.showLinkLocalIPv6) private var showLinkLocal = false
    @AppStorage(PrefKey.showTemporaryIPv6) private var showTemporary = false
    @AppStorage(PrefKey.liveInterval) private var liveInterval = 2.0
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
                Toggle("Show Dock icon", isOn: $showDockIcon)
            }

            Section("Information") {
                Picker("Network interfaces", selection: $interfaceScope) {
                    ForEach(InterfaceScope.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                }
                Picker("Disks", selection: $volumeScope) {
                    ForEach(VolumeScope.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                }
                Toggle("Include link-local IPv6 addresses (fe80::)", isOn: $showLinkLocal)
                Toggle("Include temporary (privacy) IPv6 addresses", isOn: $showTemporary)
                Picker("Live values update every", selection: $liveInterval) {
                    Text("1 second").tag(1.0)
                    Text("2 seconds").tag(2.0)
                    Text("5 seconds").tag(5.0)
                    Text("10 seconds").tag(10.0)
                }
            }

            Section {
                HStack(alignment: .firstTextBaseline) {
                    Text("Wi-Fi network name: \(location.statusText)")
                    Spacer()
                    if location.status == .notDetermined {
                        Button("Allow…") { location.requestIfNeeded() }
                    } else if !location.isAllowed {
                        Button("Open Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
            } footer: {
                Text("macOS only shares the Wi-Fi name with apps allowed to use Location Services. Nameplate never reads your location. The public IP, if you show it, is looked up at \(PublicIP.serviceHost); that's the only time Nameplate contacts the internet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                Text("In the Shortcuts app, add a “Run Shell Script” action with  /usr/local/bin/nameplate --get ip  (or serial, model, ssid, cpu, --json …). Run  nameplate --keys  in Terminal to see every value.")
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
