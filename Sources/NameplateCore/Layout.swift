import Foundation

/// What a line in the layout is.
public enum LayoutKind: String, Codable, Sendable {
    /// One of the built-in pieces of information.
    case item
    /// Your own text. Values in braces, like {ip}, are filled in.
    case text
    /// A title line, e.g. "Network".
    case heading
    /// An empty line.
    case spacer
    /// The output of a shell command, run every so often.
    case command
}

public struct LayoutEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var kind: LayoutKind
    public var item: InfoItem?
    public var enabled: Bool
    /// Replaces the built-in label. nil keeps the built-in one; a single space shows no label.
    public var label: String?
    /// The text, heading title, or shell command.
    public var text: String
    /// How often a command runs, in seconds.
    public var interval: Int

    public init(id: UUID = UUID(), kind: LayoutKind, item: InfoItem? = nil, enabled: Bool = true,
                label: String? = nil, text: String = "", interval: Int = 60) {
        self.id = id
        self.kind = kind
        self.item = item
        self.enabled = enabled
        self.label = label
        self.text = text
        self.interval = interval
    }

    public static func builtIn(_ item: InfoItem, enabled: Bool = true) -> LayoutEntry {
        LayoutEntry(kind: .item, item: item, enabled: enabled)
    }

    public static func spacer() -> LayoutEntry {
        LayoutEntry(kind: .spacer)
    }

    public static func heading(_ title: String) -> LayoutEntry {
        LayoutEntry(kind: .heading, text: title)
    }

    /// The name shown in Settings.
    public var title: String {
        switch kind {
        case .item: return item?.title ?? "Unknown item"
        case .text: return "Text"
        case .heading: return "Heading"
        case .spacer: return "Blank line"
        case .command: return "Command output"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, item, enabled, label, text, interval
    }

    // Lenient, so a setting saved by a newer version never wipes the whole layout.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        kind = (try? c.decode(LayoutKind.self, forKey: .kind)) ?? .spacer
        item = try? c.decodeIfPresent(InfoItem.self, forKey: .item)
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? true
        label = try? c.decodeIfPresent(String.self, forKey: .label)
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        interval = (try? c.decode(Int.self, forKey: .interval)) ?? 60
    }
}

/// The order and wording of everything Nameplate shows.
public struct Layout: Codable, Equatable, Sendable {
    /// The lines, top to bottom.
    public var entries: [LayoutEntry]
    /// What is shown under each network interface, top to bottom.
    public var interfaceDetails: [LayoutEntry]

    public init(entries: [LayoutEntry], interfaceDetails: [LayoutEntry]) {
        self.entries = entries
        self.interfaceDetails = interfaceDetails
    }

    enum CodingKeys: String, CodingKey {
        case entries, interfaceDetails
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        entries = (try? c.decode([LayoutEntry].self, forKey: .entries)) ?? []
        interfaceDetails = (try? c.decode([LayoutEntry].self, forKey: .interfaceDetails)) ?? []
        cleanUp()
    }

    public static let topLevelItems: [InfoItem] = InfoItem.allCases.filter { !$0.isInterfaceDetail }
    public static let detailItems: [InfoItem] = InfoItem.allCases.filter { $0.isInterfaceDetail }

    /// The standard arrangement. `isOn` decides which built-in items start switched on.
    public static func standard(isOn: (InfoItem) -> Bool = { $0.defaultOn }, headings: Bool = false) -> Layout {
        let groups: [(String, [InfoItem])] = [
            ("Hardware", [.computerName, .hostName, .model, .modelIdentifier, .serialNumber, .hardwareUUID, .chip, .memory, .graphics]),
            ("Status", [.os, .server, .user, .uptime, .bootTime, .cpuUsage, .memoryUsage, .battery, .batteryHealth, .disks]),
            ("Network", [.interfaces, .networkSpeed, .publicIP]),
        ]
        var entries: [LayoutEntry] = []
        for (index, group) in groups.enumerated() {
            if headings {
                entries.append(.heading(group.0))
            } else if index > 0 {
                entries.append(.spacer())
            }
            entries.append(contentsOf: group.1.map { LayoutEntry.builtIn($0, enabled: isOn($0)) })
        }
        let details = detailItems.map { LayoutEntry.builtIn($0, enabled: isOn($0)) }
        var layout = Layout(entries: entries, interfaceDetails: details)
        layout.addMissingItems()
        return layout
    }

    /// Everything, with section headings. Used by Copy All and the command-line tool.
    public static var everything: Layout {
        standard(isOn: { _ in true }, headings: true)
    }

    /// Adds built-in items this layout doesn't have yet (switched off), so items added
    /// in a later version show up in Settings.
    public mutating func addMissingItems() {
        for item in Layout.topLevelItems where !entries.contains(where: { $0.item == item }) {
            entries.append(.builtIn(item, enabled: false))
        }
        for item in Layout.detailItems where !interfaceDetails.contains(where: { $0.item == item }) {
            interfaceDetails.append(.builtIn(item, enabled: false))
        }
    }

    /// Drops lines this version doesn't understand and keeps each list to the items it can show.
    public mutating func cleanUp() {
        entries.removeAll { entry in
            entry.kind == .item && (entry.item == nil || entry.item!.isInterfaceDetail)
        }
        interfaceDetails.removeAll { entry in
            entry.kind != .item || entry.item == nil || !entry.item!.isInterfaceDetail
        }
        var seen = Set<InfoItem>()
        entries.removeAll { entry in
            guard let item = entry.item else { return false }
            return !seen.insert(item).inserted
        }
        seen.removeAll()
        interfaceDetails.removeAll { entry in
            guard let item = entry.item else { return false }
            return !seen.insert(item).inserted
        }
    }

    // MARK: What the layout needs

    public func uses(_ item: InfoItem) -> Bool {
        entries.contains { $0.enabled && $0.item == item }
    }

    public func usesDetail(_ item: InfoItem) -> Bool {
        uses(.interfaces) && interfaceDetails.contains { $0.enabled && $0.item == item }
    }

    /// Every text that can hold {placeholders}.
    public var templateTexts: [String] {
        entries
            .filter { $0.enabled && ($0.kind == .text || $0.kind == .heading) }
            .flatMap { [$0.text, $0.label ?? ""] }
    }

    public func usesKey(_ key: String) -> Bool {
        templateTexts.contains { InfoFormatter.keys(in: $0).contains(key) }
    }

    /// Which live numbers have to be sampled to show this layout.
    public var liveNeeds: LiveNeeds {
        var needs: LiveNeeds = []
        for entry in entries where entry.enabled && entry.kind == .item {
            if let item = entry.item { needs.formUnion(item.liveNeeds) }
        }
        for text in templateTexts {
            needs.formUnion(InfoFormatter.liveNeeds(forTemplate: text))
        }
        return needs
    }

    /// Commands that are switched on and not empty.
    public var activeCommands: [LayoutEntry] {
        entries.filter { $0.enabled && $0.kind == .command && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}
