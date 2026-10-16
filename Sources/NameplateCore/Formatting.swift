import Foundation

// MARK: - Built-in items

public enum InfoGroup: String, CaseIterable, Sendable {
    case hardware = "Hardware"
    case status = "Status"
    case live = "Live"
    case network = "Network"
    case interface = "Network interface details"
}

public enum InfoItem: String, CaseIterable, Codable, Sendable {
    // Hardware
    case computerName, hostName, model, modelIdentifier, serialNumber, hardwareUUID, chip, memory, graphics
    // Status
    case os, server, user, uptime, bootTime, disks
    // Live
    case cpuUsage, memoryUsage, battery, batteryHealth, networkSpeed
    // Network
    case interfaces, publicIP
    // Shown under each network interface
    case wifiName, ipv4, subnetMask, router, configMethod, ipv6, macAddress, dns, searchDomains, wifiSignal

    /// The name in Settings.
    public var title: String {
        switch self {
        case .computerName: return "Computer name"
        case .hostName: return "Local host name"
        case .model: return "Model"
        case .modelIdentifier: return "Model identifier"
        case .serialNumber: return "Serial number"
        case .hardwareUUID: return "Hardware UUID"
        case .chip: return "Chip / processor"
        case .memory: return "Memory installed"
        case .graphics: return "Graphics"
        case .os: return "macOS version"
        case .server: return "Server version"
        case .user: return "Current user"
        case .uptime: return "Uptime"
        case .bootTime: return "Boot time"
        case .disks: return "Disk space"
        case .cpuUsage: return "CPU usage (live)"
        case .memoryUsage: return "Memory in use (live)"
        case .battery: return "Battery (live)"
        case .batteryHealth: return "Battery health"
        case .networkSpeed: return "Network traffic (live)"
        case .interfaces: return "Network interfaces"
        case .publicIP: return "Public IP address"
        case .wifiName: return "Wi-Fi network name"
        case .ipv4: return "IPv4 address"
        case .subnetMask: return "Subnet mask"
        case .router: return "Router"
        case .configMethod: return "Configuration (DHCP / manual)"
        case .ipv6: return "IPv6 address"
        case .macAddress: return "MAC address"
        case .dns: return "DNS servers"
        case .searchDomains: return "Search domains"
        case .wifiSignal: return "Wi-Fi signal, channel and speed"
        }
    }

    /// The label shown next to the value unless you rename it.
    public var defaultLabel: String {
        switch self {
        case .computerName: return "Computer"
        case .hostName: return "Host Name"
        case .model: return "Model"
        case .modelIdentifier: return "Model ID"
        case .serialNumber: return "Serial"
        case .hardwareUUID: return "Hardware UUID"
        case .chip: return "Chip"
        case .memory: return "Memory"
        case .graphics: return "Graphics"
        case .os: return "macOS"
        case .server: return "Server"
        case .user: return "User"
        case .uptime: return "Uptime"
        case .bootTime: return "Booted"
        case .disks: return "Disk"
        case .cpuUsage: return "CPU"
        case .memoryUsage: return "Memory Used"
        case .battery: return "Battery"
        case .batteryHealth: return "Battery Health"
        case .networkSpeed: return "Traffic"
        case .interfaces: return ""
        case .publicIP: return "Public IP"
        case .wifiName: return "SSID"
        case .ipv4: return "IPv4"
        case .subnetMask: return "Subnet"
        case .router: return "Router"
        case .configMethod: return "Config"
        case .ipv6: return "IPv6"
        case .macAddress: return "MAC"
        case .dns: return "DNS"
        case .searchDomains: return "Search"
        case .wifiSignal: return "Signal"
        }
    }

    public var group: InfoGroup {
        switch self {
        case .computerName, .hostName, .model, .modelIdentifier, .serialNumber, .hardwareUUID, .chip, .memory, .graphics:
            return .hardware
        case .os, .server, .user, .uptime, .bootTime, .disks:
            return .status
        case .cpuUsage, .memoryUsage, .battery, .batteryHealth, .networkSpeed:
            return .live
        case .interfaces, .publicIP:
            return .network
        case .wifiName, .ipv4, .subnetMask, .router, .configMethod, .ipv6, .macAddress, .dns, .searchDomains, .wifiSignal:
            return .interface
        }
    }

    public var defaultOn: Bool {
        switch self {
        case .hostName, .modelIdentifier, .hardwareUUID, .bootTime, .searchDomains, .wifiSignal, .publicIP,
             .cpuUsage, .memoryUsage, .battery, .batteryHealth, .networkSpeed:
            return false
        default:
            return true
        }
    }

    public var isInterfaceDetail: Bool { group == .interface }

    public var liveNeeds: LiveNeeds {
        switch self {
        case .cpuUsage: return .cpu
        case .memoryUsage: return .memory
        case .battery, .batteryHealth: return .battery
        case .networkSpeed: return .network
        default: return []
        }
    }

    public static func items(in group: InfoGroup) -> [InfoItem] {
        allCases.filter { $0.group == group }
    }
}

public enum InterfaceScope: String, CaseIterable, Sendable {
    case primary, active
    public var title: String { self == .primary ? "Primary interface only" : "All active interfaces" }
}

public enum VolumeScope: String, CaseIterable, Sendable {
    case startup, local, all
    public var title: String {
        switch self {
        case .startup: return "Startup disk only"
        case .local: return "All local disks"
        case .all: return "All disks, including network"
        }
    }
}

/// Choices that affect what the lines contain.
public struct RenderSettings: Equatable, Sendable {
    public var interfaceScope: InterfaceScope
    public var volumeScope: VolumeScope
    public var showLinkLocalIPv6: Bool
    public var showTemporaryIPv6: Bool

    public init(interfaceScope: InterfaceScope, volumeScope: VolumeScope, showLinkLocalIPv6: Bool, showTemporaryIPv6: Bool) {
        self.interfaceScope = interfaceScope
        self.volumeScope = volumeScope
        self.showLinkLocalIPv6 = showLinkLocalIPv6
        self.showTemporaryIPv6 = showTemporaryIPv6
    }

    public static let everything = RenderSettings(interfaceScope: .active, volumeScope: .all,
                                                  showLinkLocalIPv6: false, showTemporaryIPv6: true)
}

/// Everything the lines are made from.
public struct RenderInput: Sendable {
    public var snapshot: SystemSnapshot
    public var live: LiveStats
    public var commandOutputs: [UUID: String]
    public var now: Date

    public init(snapshot: SystemSnapshot, live: LiveStats = LiveStats(), commandOutputs: [UUID: String] = [:], now: Date = Date()) {
        self.snapshot = snapshot
        self.live = live
        self.commandOutputs = commandOutputs
        self.now = now
    }
}

// MARK: - Lines

public struct InfoLine: Identifiable, Equatable, Sendable {
    public enum Kind: Sendable { case section, subheader, row, spacer }
    public var id: Int
    public var kind: Kind
    public var label: String
    public var value: String
    /// 0...1 for things that can be drawn as a bar (disk, CPU, memory, battery).
    public var fraction: Double?
    /// Draw the bar in a warning color.
    public var warn: Bool
    /// A second value for the line above (e.g. another DNS server); it shares that label.
    public var isContinuation: Bool

    public init(id: Int = 0, kind: Kind, label: String = "", value: String = "",
                fraction: Double? = nil, warn: Bool = false, isContinuation: Bool = false) {
        self.id = id
        self.kind = kind
        self.label = label
        self.value = value
        self.fraction = fraction
        self.warn = warn
        self.isContinuation = isContinuation
    }
}

public struct TemplateKey: Sendable {
    public let key: String
    public let title: String
}

public struct TemplateKeyGroup: Sendable {
    public let name: String
    public let keys: [TemplateKey]

    init(_ name: String, _ pairs: [(String, String)]) {
        self.name = name
        self.keys = pairs.map { TemplateKey(key: $0.0, title: $0.1) }
    }
}

public struct InfoValue: Equatable, Sendable {
    public var key: String
    public var label: String
    public var value: String
}

public enum InfoFormatter {

    // MARK: Lines from a layout

    public static func lines(layout: Layout, input: RenderInput, settings: RenderSettings) -> [InfoLine] {
        var out: [InfoLine] = []
        var cachedValues: [String: String]?
        func values() -> [String: String] {
            if let cachedValues { return cachedValues }
            let made = valueDictionary(input)
            cachedValues = made
            return made
        }

        for entry in layout.entries where entry.enabled {
            switch entry.kind {
            case .spacer:
                out.append(InfoLine(kind: .spacer))
            case .heading:
                let title = render(template: entry.text, values: values()).trimmingCharacters(in: .whitespaces)
                if !title.isEmpty { out.append(InfoLine(kind: .section, value: title)) }
            case .text:
                let value = render(template: entry.text, values: values())
                let label = entry.label.map { render(template: $0, values: values()) } ?? ""
                if !value.trimmingCharacters(in: .whitespaces).isEmpty || !label.trimmingCharacters(in: .whitespaces).isEmpty {
                    out.append(InfoLine(kind: .row, label: label, value: value))
                }
            case .command:
                guard !entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                let output = input.commandOutputs[entry.id] ?? "…"
                guard !output.isEmpty else { continue }
                let rows = output.components(separatedBy: "\n").prefix(12)
                for (index, text) in rows.enumerated() {
                    out.append(InfoLine(kind: .row, label: index == 0 ? (entry.label ?? "") : "",
                                        value: String(text.prefix(200)), isContinuation: index > 0))
                }
            case .item:
                guard let item = entry.item else { continue }
                if item == .interfaces {
                    out.append(contentsOf: interfaceLines(input.snapshot, details: layout.interfaceDetails, settings: settings))
                } else {
                    out.append(contentsOf: itemLines(item, customLabel: entry.label, input: input, settings: settings))
                }
            }
        }
        return tidy(out)
    }

    /// Drops blank lines at the ends, doubled blank lines, and blank lines right before a heading.
    static func tidy(_ lines: [InfoLine]) -> [InfoLine] {
        var result: [InfoLine] = []
        for line in lines {
            if line.kind == .spacer {
                if result.isEmpty || result.last?.kind == .spacer || result.last?.kind == .section { continue }
            }
            if line.kind == .section, result.last?.kind == .spacer {
                result.removeLast()
            }
            result.append(line)
        }
        while result.last?.kind == .spacer { result.removeLast() }
        for index in result.indices { result[index].id = index }
        return result
    }

    static func itemLines(_ item: InfoItem, customLabel: String?, input: RenderInput, settings: RenderSettings) -> [InfoLine] {
        let s = input.snapshot
        let live = input.live
        var label = customLabel ?? item.defaultLabel
        if customLabel == nil && item == .chip && !s.isAppleSilicon { label = "Processor" }

        func one(_ value: String?, fraction: Double? = nil, warn: Bool = false) -> [InfoLine] {
            guard let value, !value.isEmpty else { return [] }
            return [InfoLine(kind: .row, label: label, value: value, fraction: fraction, warn: warn)]
        }
        func many(_ values: [String]) -> [InfoLine] {
            values.filter { !$0.isEmpty }.enumerated().map { pair in
                InfoLine(kind: .row, label: pair.offset == 0 ? label : "", value: pair.element, isContinuation: pair.offset > 0)
            }
        }

        switch item {
        case .computerName: return one(s.computerName)
        case .hostName: return one(s.localHostName ?? s.hostName)
        case .model: return one(s.model)
        case .modelIdentifier: return one(s.modelIdentifier)
        case .serialNumber: return one(s.serialNumber)
        case .hardwareUUID: return one(s.hardwareUUID)
        case .chip: return one(chipText(s))
        case .memory: return one(memoryText(s.memoryBytes))
        case .graphics: return many(s.gpus.map { gpuText($0) })
        case .os: return one(osText(s.os))
        case .server: return one(s.serverVersion)
        case .user: return one(userText(s))
        case .uptime: return one(uptimeText(s.uptimeSeconds))
        case .bootTime: return one(dateText(s.bootTime))
        case .disks:
            return volumes(s, scope: settings.volumeScope).enumerated().map { pair in
                InfoLine(kind: .row, label: pair.offset == 0 ? label : "", value: diskText(pair.element),
                         fraction: pair.element.usedFraction, warn: pair.element.usedFraction >= 0.9,
                         isContinuation: pair.offset > 0)
            }
        case .cpuUsage:
            guard let cpu = live.cpuUsage else { return one("…") }
            return one(percentText(cpu), fraction: cpu, warn: cpu >= 0.9)
        case .memoryUsage:
            guard let used = live.memoryUsed, let total = live.memoryTotal, total > 0 else { return [] }
            let fraction = Double(used) / Double(total)
            var text = "\(gigabytes(used)) of \(memoryText(total)) (\(percentText(fraction)))"
            let pressure = live.memoryPressure ?? .normal
            if pressure != .normal { text += " · \(pressure.title) pressure" }
            return one(text, fraction: fraction, warn: pressure != .normal)
        case .battery:
            guard let battery = live.battery else { return [] }
            return one(batteryText(battery), fraction: Double(battery.percent) / 100,
                       warn: battery.percent <= 15 && !battery.isOnPower)
        case .batteryHealth:
            guard let battery = live.battery else { return [] }
            return one(batteryHealthText(battery))
        case .networkSpeed:
            guard let down = live.downBytesPerSecond, let up = live.upBytesPerSecond else {
                return one(s.network.primaryInterface == nil ? nil : "…")
            }
            return one("↓ \(rateText(down))   ↑ \(rateText(up))")
        case .publicIP:
            return one(s.publicIP ?? "Looking up…")
        default:
            // Interface details only appear inside the interfaces block.
            return []
        }
    }

    static func interfaceLines(_ s: SystemSnapshot, details: [LayoutEntry], settings: RenderSettings) -> [InfoLine] {
        let interfaces = settings.interfaceScope == .primary
            ? (s.network.primary.map { [$0] } ?? [])
            : s.network.interfaces
        if interfaces.isEmpty {
            return [InfoLine(kind: .row, label: "Network", value: "Not connected")]
        }
        var out: [InfoLine] = []
        for iface in interfaces {
            var title = "\(iface.displayName) (\(iface.name))"
            if iface.isPrimary && interfaces.count > 1 { title += " · primary" }
            out.append(InfoLine(kind: .subheader, value: title))

            for entry in details where entry.enabled {
                guard let item = entry.item else { continue }
                let label = entry.label ?? item.defaultLabel
                var values: [String] = []
                switch item {
                case .wifiName:
                    if let ssid = iface.wifi?.ssid { values = [ssid] }
                case .ipv4:
                    values = iface.ipv4.map { $0.address }
                case .subnetMask:
                    if let first = iface.ipv4.first, let mask = first.subnetMask {
                        values = [mask + (first.prefixLength.map { length in " (/\(length))" } ?? "")]
                    }
                case .router:
                    if let router = iface.router { values = [router] }
                case .configMethod:
                    if let config = configText(iface) { values = [config] }
                case .ipv6:
                    values = iface.ipv6
                        .filter { address in
                            (address.isLinkLocal ? settings.showLinkLocalIPv6 : true)
                                && (address.isTemporary ? settings.showTemporaryIPv6 : true)
                        }
                        .map { address in address.address + (address.prefixLength.map { length in "/\(length)" } ?? "") }
                case .macAddress:
                    if let mac = iface.macAddress { values = [mac] }
                case .dns:
                    values = iface.dnsServers
                case .searchDomains:
                    if !iface.searchDomains.isEmpty { values = [iface.searchDomains.joined(separator: ", ")] }
                case .wifiSignal:
                    if let wifi = iface.wifi, let text = wifiText(wifi) { values = [text] }
                default:
                    break
                }
                for (index, value) in values.filter({ !$0.isEmpty }).enumerated() {
                    out.append(InfoLine(kind: .row, label: index == 0 ? label : "", value: value, isContinuation: index > 0))
                }
            }
        }
        return out
    }

    // MARK: Plain text and JSON

    /// Plain text for the clipboard.
    public static func plainText(_ lines: [InfoLine]) -> String {
        var out: [String] = []
        var lastLabel = ""
        var insideInterface = false
        for line in lines {
            switch line.kind {
            case .section:
                if let last = out.last, !last.isEmpty { out.append("") }
                out.append(line.value.uppercased())
                insideInterface = false
            case .subheader:
                out.append(line.value + ":")
                insideInterface = true
            case .spacer:
                out.append("")
                insideInterface = false
            case .row:
                let label = line.isContinuation ? lastLabel : line.label.trimmingCharacters(in: .whitespaces)
                if !line.isContinuation { lastLabel = label }
                let indent = insideInterface ? "  " : ""
                out.append(label.isEmpty ? indent + line.value : "\(indent)\(label): \(line.value)")
            }
        }
        return out.joined(separator: "\n")
    }

    public static func json(_ snapshot: SystemSnapshot) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Values by key (for {placeholders}, `nameplate --get` and Shortcuts)

    /// The keys offered in Settings' Insert menus, grouped.
    public static let templateKeys: [TemplateKeyGroup] = [
        TemplateKeyGroup("Computer", [
            ("computer-name", "Computer name"), ("local-hostname", "Local host name"), ("model", "Model"),
            ("model-id", "Model identifier"), ("serial", "Serial number"), ("chip", "Chip"), ("cores", "CPU cores"),
            ("memory", "Memory installed"), ("gpu", "Graphics"),
        ]),
        TemplateKeyGroup("System", [
            ("os", "macOS name and version"), ("os-version", "macOS version"), ("os-build", "macOS build"),
            ("user", "User name"), ("user-full-name", "User full name"), ("uptime", "Uptime"),
            ("uptime-short", "Uptime, short"), ("boot-time", "Boot time"),
        ]),
        TemplateKeyGroup("Live", [
            ("cpu", "CPU usage"), ("memory-used", "Memory used"), ("memory-percent", "Memory used (%)"),
            ("memory-pressure", "Memory pressure"), ("battery", "Battery level"), ("battery-status", "Battery status"),
            ("battery-time", "Battery time left"), ("battery-health", "Battery health"), ("battery-cycles", "Battery cycles"),
            ("down", "Download speed"), ("up", "Upload speed"),
        ]),
        TemplateKeyGroup("Disk", [
            ("disk-free", "Startup disk free"), ("disk-total", "Startup disk size"),
            ("disk-used-percent", "Startup disk used (%)"), ("disk", "Startup disk summary"),
        ]),
        TemplateKeyGroup("Network", [
            ("ip", "IPv4 address"), ("ipv6", "IPv6 address"), ("subnet", "Subnet mask"), ("router", "Router"),
            ("dns", "DNS servers"), ("mac", "MAC address"), ("ssid", "Wi-Fi network name"),
            ("service", "Network name (e.g. Wi-Fi)"), ("interface", "Interface (e.g. en0)"), ("public-ip", "Public IP"),
        ]),
        TemplateKeyGroup("Date and time", [
            ("date", "Date"), ("time", "Time"), ("day", "Day of the week"),
        ]),
    ]

    public static func values(for input: RenderInput) -> [InfoValue] {
        let s = input.snapshot
        let live = input.live
        var list: [InfoValue] = []
        func add(_ key: String, _ label: String, _ value: String?) {
            guard let value, !value.isEmpty else { return }
            list.append(InfoValue(key: key, label: label, value: value))
        }
        add("computer-name", "Computer name", s.computerName)
        add("local-hostname", "Local host name", s.localHostName)
        add("hostname", "Host name", s.hostName)
        add("model", "Model", s.model)
        add("model-id", "Model identifier", s.modelIdentifier)
        add("serial", "Serial number", s.serialNumber)
        add("uuid", "Hardware UUID", s.hardwareUUID)
        add("chip", "Chip", s.chip)
        add("cores", "CPU cores", String(s.cpuCores.total))
        add("memory", "Memory", memoryText(s.memoryBytes))
        add("memory-bytes", "Memory (bytes)", String(s.memoryBytes))
        add("gpu", "Graphics", s.gpus.map { gpuText($0) }.joined(separator: ", "))
        add("os", "macOS", osText(s.os))
        add("os-version", "macOS version", s.os.version)
        add("os-build", "macOS build", s.os.build)
        add("server", "Server version", s.serverVersion)
        add("user", "User", s.userName)
        add("user-full-name", "User full name", s.userFullName)
        add("uptime", "Uptime", uptimeText(s.uptimeSeconds))
        add("uptime-short", "Uptime (short)", shortUptimeText(s.uptimeSeconds))
        add("uptime-seconds", "Uptime (seconds)", String(s.uptimeSeconds))
        add("boot-time", "Boot time", dateText(s.bootTime))

        if let cpu = live.cpuUsage { add("cpu", "CPU usage", percentText(cpu)) }
        if let used = live.memoryUsed, let total = live.memoryTotal, total > 0 {
            add("memory-used", "Memory used", gigabytes(used))
            add("memory-percent", "Memory used (%)", percentText(Double(used) / Double(total)))
        }
        add("memory-pressure", "Memory pressure", live.memoryPressure?.title)
        if let battery = live.battery {
            add("battery", "Battery", "\(battery.percent)%")
            add("battery-status", "Battery status", batteryStatusText(battery))
            add("battery-time", "Battery time left", batteryTimeText(battery))
            add("battery-health", "Battery health", battery.healthPercent.map { "\($0)%" })
            add("battery-cycles", "Battery cycles", battery.cycleCount.map { String($0) })
        }
        if let down = live.downBytesPerSecond { add("down", "Download speed", rateText(down)) }
        if let up = live.upBytesPerSecond { add("up", "Upload speed", rateText(up)) }

        if let startup = s.volumes.first(where: { $0.isStartup }) ?? s.volumes.first {
            add("disk", "Startup disk", diskText(startup))
            add("disk-free", "Startup disk free", bytes(startup.availableBytes))
            add("disk-free-bytes", "Startup disk free (bytes)", String(startup.availableBytes))
            add("disk-total", "Startup disk size", bytes(startup.totalBytes))
            add("disk-used-percent", "Startup disk used (%)", String(Int((startup.usedFraction * 100).rounded())))
        }
        if let p = s.network.primary {
            add("interface", "Primary interface", p.name)
            add("service", "Primary service", p.displayName)
            add("ip", "IPv4 address", p.ipv4.first?.address)
            add("subnet", "Subnet mask", p.ipv4.first?.subnetMask)
            add("router", "Router", p.router)
            add("config", "Configuration", configText(p))
            add("ipv6", "IPv6 address", p.ipv6.first(where: { !$0.isLinkLocal && !$0.isTemporary })?.address
                ?? p.ipv6.first(where: { !$0.isLinkLocal })?.address)
            add("mac", "MAC address", p.macAddress)
            add("ssid", "Wi-Fi network", p.wifi?.ssid)
        }
        add("dns", "DNS servers", s.network.dnsServers.joined(separator: ", "))
        add("search-domains", "Search domains", s.network.searchDomains.joined(separator: ", "))
        add("public-ip", "Public IP", s.publicIP)
        for iface in s.network.interfaces {
            add("\(iface.name).ip", "\(iface.displayName) IPv4", iface.ipv4.map { $0.address }.joined(separator: ", "))
            add("\(iface.name).ipv6", "\(iface.displayName) IPv6", iface.ipv6.filter { !$0.isLinkLocal }.map { $0.address }.joined(separator: ", "))
            add("\(iface.name).router", "\(iface.displayName) router", iface.router)
            add("\(iface.name).mac", "\(iface.displayName) MAC", iface.macAddress)
            add("\(iface.name).ssid", "\(iface.displayName) network", iface.wifi?.ssid)
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none
        add("date", "Date", dateFormatter.string(from: input.now))
        dateFormatter.dateStyle = .none
        dateFormatter.timeStyle = .short
        add("time", "Time", dateFormatter.string(from: input.now))
        dateFormatter.setLocalizedDateFormatFromTemplate("EEEE")
        add("day", "Day", dateFormatter.string(from: input.now))
        return list
    }

    public static func valueDictionary(_ input: RenderInput) -> [String: String] {
        var result: [String: String] = [:]
        for value in values(for: input) where result[value.key] == nil {
            result[value.key] = value.value
        }
        return result
    }

    /// Every key Nameplate knows about, whether or not it has a value right now.
    static let knownKeys: Set<String> = {
        var keys = Set(templateKeys.flatMap { group in group.keys.map { $0.key } })
        keys.formUnion(["hostname", "memory-bytes", "server", "uptime-seconds", "disk-free-bytes", "config",
                        "search-domains", "uuid"])
        return keys
    }()

    /// Fills in {key} placeholders. Known keys with no value right now become empty;
    /// anything else in braces is left as typed, so a typo is easy to spot.
    public static func render(template: String, values: [String: String]) -> String {
        guard template.contains("{") else { return template }
        var result = ""
        var rest = Substring(template)
        while let open = rest.firstIndex(of: "{") {
            result += rest[..<open]
            let afterOpen = rest[rest.index(after: open)...]
            guard let close = afterOpen.firstIndex(of: "}") else {
                result += rest[open...]
                return result
            }
            let raw = String(afterOpen[..<close])
            let key = raw.trimmingCharacters(in: .whitespaces).lowercased()
            if let value = values[key] {
                result += value
            } else if !knownKeys.contains(key) && !key.contains(".") {
                result += "{" + raw + "}"
            }
            rest = afterOpen[afterOpen.index(after: close)...]
        }
        result += rest
        return result
    }

    /// The keys used in a template, lowercased.
    public static func keys(in template: String) -> [String] {
        var keys: [String] = []
        var rest = Substring(template)
        while let open = rest.firstIndex(of: "{") {
            let afterOpen = rest[rest.index(after: open)...]
            guard let close = afterOpen.firstIndex(of: "}") else { break }
            keys.append(String(afterOpen[..<close]).trimmingCharacters(in: .whitespaces).lowercased())
            rest = afterOpen[afterOpen.index(after: close)...]
        }
        return keys
    }

    public static func liveNeeds(forTemplate template: String) -> LiveNeeds {
        var needs: LiveNeeds = []
        for key in keys(in: template) {
            switch key {
            case "cpu": needs.insert(.cpu)
            case "memory-used", "memory-percent", "memory-pressure": needs.insert(.memory)
            case "down", "up": needs.insert(.network)
            case "time", "date", "day": needs.insert(.clock)
            default:
                if key.hasPrefix("battery") { needs.insert(.battery) }
            }
        }
        return needs
    }

    // MARK: Pieces

    public static func chipText(_ s: SystemSnapshot) -> String {
        let c = s.cpuCores
        if let p = c.performance, let e = c.efficiency, p > 0, e > 0 {
            return "\(s.chip) (\(c.total)-core: \(p)P + \(e)E)"
        }
        if let threads = c.threads {
            return "\(s.chip) (\(c.total)-core, \(threads) threads)"
        }
        return "\(s.chip) (\(c.total)-core)"
    }

    public static func memoryText(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        return gb >= 1 ? "\(Int(gb.rounded())) GB" : ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }

    static func gigabytes(_ bytes: UInt64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_073_741_824)
    }

    public static func gpuText(_ gpu: GPUInfo) -> String {
        guard let cores = gpu.cores, cores > 0 else { return gpu.name }
        return "\(gpu.name) (\(cores)-core GPU)"
    }

    public static func osText(_ os: OSInfo) -> String {
        os.build.isEmpty ? "\(os.name) \(os.version)" : "\(os.name) \(os.version) (\(os.build))"
    }

    public static func userText(_ s: SystemSnapshot) -> String {
        s.userFullName.isEmpty || s.userFullName == s.userName ? s.userName : "\(s.userFullName) (\(s.userName))"
    }

    public static func uptimeText(_ seconds: Int) -> String {
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        var parts: [String] = []
        if days > 0 { parts.append(days == 1 ? "1 day" : "\(days) days") }
        if hours > 0 { parts.append(hours == 1 ? "1 hour" : "\(hours) hours") }
        if days == 0 { parts.append(minutes == 1 ? "1 minute" : "\(minutes) minutes") }
        return parts.joined(separator: ", ")
    }

    static func shortUptimeText(_ seconds: Int) -> String {
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    public static func dateText(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    public static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    public static func diskText(_ v: VolumeInfo) -> String {
        "\(v.name): \(bytes(v.availableBytes)) free of \(bytes(v.totalBytes))"
    }

    static func percentText(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    static func rateText(_ bytesPerSecond: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: Int64(max(0, bytesPerSecond))) + "/s"
    }

    static func durationText(minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    static func batteryStatusText(_ b: BatteryInfo) -> String {
        if b.isCharging { return "Charging" }
        if b.isCharged || (b.isOnPower && b.percent >= 95) { return "Charged" }
        if b.isOnPower { return "On power, not charging" }
        return "On battery"
    }

    static func batteryTimeText(_ b: BatteryInfo) -> String? {
        if b.isCharging, let minutes = b.minutesToFull { return "\(durationText(minutes: minutes)) to full" }
        if !b.isOnPower, let minutes = b.minutesToEmpty { return "\(durationText(minutes: minutes)) left" }
        return nil
    }

    static func batteryText(_ b: BatteryInfo) -> String {
        var parts = ["\(b.percent)%", batteryStatusText(b)]
        if let time = batteryTimeText(b) { parts.append(time) }
        return parts.joined(separator: " · ")
    }

    static func batteryHealthText(_ b: BatteryInfo) -> String? {
        var parts: [String] = []
        if let health = b.healthPercent { parts.append("\(health)%") }
        if let cycles = b.cycleCount { parts.append(cycles == 1 ? "1 cycle" : "\(cycles) cycles") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    public static func configText(_ iface: InterfaceInfo) -> String? {
        guard let method = iface.configMethod else { return nil }
        if let server = iface.dhcpServer, method.hasPrefix("DHCP") { return "\(method) from \(server)" }
        return method
    }

    public static func wifiText(_ w: WiFiInfo) -> String? {
        var parts: [String] = []
        if let rssi = w.rssi { parts.append("\(rssi) dBm") }
        if let channel = w.channel { parts.append(w.band.map { "Ch \(channel) (\($0))" } ?? "Ch \(channel)") }
        if let rate = w.transmitRateMbps { parts.append("\(Int(rate.rounded())) Mbps") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func volumes(_ s: SystemSnapshot, scope: VolumeScope) -> [VolumeInfo] {
        switch scope {
        case .startup:
            if let startup = s.volumes.first(where: { $0.isStartup }) { return [startup] }
            return Array(s.volumes.prefix(1))
        case .local:
            return s.volumes.filter { $0.isLocal }
        case .all:
            return s.volumes
        }
    }
}
