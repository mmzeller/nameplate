import Foundation

// MARK: - What can be shown

public enum InfoGroup: String, CaseIterable, Sendable {
    case hardware = "Hardware"
    case status = "Status"
    case network = "Network"
}

public enum InfoItem: String, CaseIterable, Codable, Sendable {
    // Hardware
    case computerName, hostName, model, modelIdentifier, serialNumber, hardwareUUID, chip, memory, graphics
    // Status
    case os, server, user, uptime, bootTime, disks
    // Network
    case interfaces, ipv4, subnetMask, router, configMethod, ipv6, macAddress, dns, searchDomains, wifiName, wifiSignal, publicIP

    public var title: String {
        switch self {
        case .computerName: return "Computer name"
        case .hostName: return "Local host name"
        case .model: return "Model"
        case .modelIdentifier: return "Model identifier"
        case .serialNumber: return "Serial number"
        case .hardwareUUID: return "Hardware UUID"
        case .chip: return "Chip / processor"
        case .memory: return "Memory"
        case .graphics: return "Graphics"
        case .os: return "macOS version"
        case .server: return "Server version (if installed)"
        case .user: return "Current user"
        case .uptime: return "Uptime"
        case .bootTime: return "Boot time"
        case .disks: return "Disk space"
        case .interfaces: return "Network interfaces"
        case .ipv4: return "IPv4 address"
        case .subnetMask: return "Subnet mask"
        case .router: return "Router"
        case .configMethod: return "Configuration (DHCP / manual)"
        case .ipv6: return "IPv6 address"
        case .macAddress: return "MAC address"
        case .dns: return "DNS servers"
        case .searchDomains: return "Search domains"
        case .wifiName: return "Wi-Fi network name"
        case .wifiSignal: return "Wi-Fi signal, channel and speed"
        case .publicIP: return "Public IP address"
        }
    }

    public var group: InfoGroup {
        switch self {
        case .computerName, .hostName, .model, .modelIdentifier, .serialNumber, .hardwareUUID, .chip, .memory, .graphics:
            return .hardware
        case .os, .server, .user, .uptime, .bootTime, .disks:
            return .status
        default:
            return .network
        }
    }

    public var defaultOn: Bool {
        switch self {
        case .hostName, .modelIdentifier, .hardwareUUID, .bootTime, .searchDomains, .wifiSignal, .publicIP:
            return false
        default:
            return true
        }
    }

    /// Items that only make sense when network interfaces are shown.
    public var dependsOnInterfaces: Bool {
        group == .network && self != .interfaces && self != .publicIP
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

public struct DisplayOptions: Equatable, Sendable {
    public var enabled: Set<InfoItem>
    public var interfaceScope: InterfaceScope
    public var volumeScope: VolumeScope
    public var showSectionTitles: Bool
    public var showLinkLocalIPv6: Bool
    public var showTemporaryIPv6: Bool

    public init(enabled: Set<InfoItem>, interfaceScope: InterfaceScope, volumeScope: VolumeScope,
                showSectionTitles: Bool, showLinkLocalIPv6: Bool, showTemporaryIPv6: Bool) {
        self.enabled = enabled
        self.interfaceScope = interfaceScope
        self.volumeScope = volumeScope
        self.showSectionTitles = showSectionTitles
        self.showLinkLocalIPv6 = showLinkLocalIPv6
        self.showTemporaryIPv6 = showTemporaryIPv6
    }

    public func has(_ item: InfoItem) -> Bool { enabled.contains(item) }

    /// Used by Copy All and the command-line tool.
    public static let everything = DisplayOptions(
        enabled: Set(InfoItem.allCases), interfaceScope: .active, volumeScope: .all,
        showSectionTitles: true, showLinkLocalIPv6: false, showTemporaryIPv6: true)

    public static let standard = DisplayOptions(
        enabled: Set(InfoItem.allCases.filter(\.defaultOn)), interfaceScope: .active, volumeScope: .startup,
        showSectionTitles: false, showLinkLocalIPv6: false, showTemporaryIPv6: false)
}

// MARK: - Lines

public struct InfoLine: Identifiable, Equatable, Sendable {
    public enum Kind: Sendable { case section, subheader, row, spacer }
    public var id: Int
    public var kind: Kind
    public var label: String
    public var value: String
}

public struct InfoValue: Equatable, Sendable {
    public var key: String
    public var label: String
    public var value: String
}

public enum InfoFormatter {

    // MARK: Display lines

    public static func lines(for s: SystemSnapshot, options o: DisplayOptions) -> [InfoLine] {
        var sections: [(InfoGroup, [InfoLine])] = []

        // Hardware
        var hw: [InfoLine] = []
        func row(_ list: inout [InfoLine], _ label: String, _ value: String?) {
            guard let value, !value.isEmpty else { return }
            list.append(InfoLine(id: 0, kind: .row, label: label, value: value))
        }
        if o.has(.computerName) { row(&hw, "Computer", s.computerName) }
        if o.has(.hostName) { row(&hw, "Host Name", s.localHostName ?? s.hostName) }
        if o.has(.model) { row(&hw, "Model", s.model) }
        if o.has(.modelIdentifier) { row(&hw, "Model ID", s.modelIdentifier) }
        if o.has(.serialNumber) { row(&hw, "Serial", s.serialNumber) }
        if o.has(.hardwareUUID) { row(&hw, "Hardware UUID", s.hardwareUUID) }
        if o.has(.chip) { row(&hw, s.isAppleSilicon ? "Chip" : "Processor", chipText(s)) }
        if o.has(.memory) { row(&hw, "Memory", memoryText(s.memoryBytes)) }
        if o.has(.graphics) {
            for (i, gpu) in s.gpus.enumerated() { row(&hw, i == 0 ? "Graphics" : "", gpuText(gpu)) }
        }
        sections.append((.hardware, hw))

        // Status
        var st: [InfoLine] = []
        if o.has(.os) { row(&st, "macOS", osText(s.os)) }
        if o.has(.server) { row(&st, "Server", s.serverVersion) }
        if o.has(.user) { row(&st, "User", userText(s)) }
        if o.has(.uptime) { row(&st, "Uptime", uptimeText(s.uptimeSeconds)) }
        if o.has(.bootTime) { row(&st, "Booted", dateText(s.bootTime)) }
        if o.has(.disks) {
            for (i, volume) in volumes(s, scope: o.volumeScope).enumerated() {
                row(&st, i == 0 ? "Disk" : "", diskText(volume))
            }
        }
        sections.append((.status, st))

        // Network
        var net: [InfoLine] = []
        if o.has(.interfaces) {
            let interfaces = o.interfaceScope == .primary
                ? Array(s.network.primary.map { [$0] } ?? [])
                : s.network.interfaces
            if interfaces.isEmpty {
                row(&net, "Network", "Not connected")
            }
            for iface in interfaces {
                var title = "\(iface.displayName) (\(iface.name))"
                if iface.isPrimary && interfaces.count > 1 { title += " · primary" }
                net.append(InfoLine(id: 0, kind: .subheader, label: "", value: title))

                if o.has(.wifiName), let ssid = iface.wifi?.ssid { row(&net, "SSID", ssid) }
                if o.has(.ipv4) {
                    for (i, a) in iface.ipv4.enumerated() { row(&net, i == 0 ? "IPv4" : "", a.address) }
                }
                if o.has(.subnetMask), let mask = iface.ipv4.first?.subnetMask {
                    let prefix = iface.ipv4.first?.prefixLength.map { " (/\($0))" } ?? ""
                    row(&net, "Subnet", mask + prefix)
                }
                if o.has(.router) { row(&net, "Router", iface.router) }
                if o.has(.configMethod) { row(&net, "Config", configText(iface)) }
                if o.has(.ipv6) {
                    let shown = iface.ipv6.filter {
                        ($0.isLinkLocal ? o.showLinkLocalIPv6 : true) && ($0.isTemporary ? o.showTemporaryIPv6 : true)
                    }
                    for (i, a) in shown.enumerated() {
                        let prefix = a.prefixLength.map { "/\($0)" } ?? ""
                        row(&net, i == 0 ? "IPv6" : "", a.address + prefix)
                    }
                }
                if o.has(.macAddress) { row(&net, "MAC", iface.macAddress) }
                if o.has(.dns), !iface.dnsServers.isEmpty {
                    for (i, server) in iface.dnsServers.enumerated() { row(&net, i == 0 ? "DNS" : "", server) }
                }
                if o.has(.searchDomains), !iface.searchDomains.isEmpty {
                    row(&net, "Search", iface.searchDomains.joined(separator: ", "))
                }
                if o.has(.wifiSignal), let wifi = iface.wifi { row(&net, "Signal", wifiText(wifi)) }
            }
        }
        if o.has(.publicIP) {
            if !net.isEmpty && net.last?.kind != .spacer { net.append(InfoLine(id: 0, kind: .spacer, label: "", value: "")) }
            row(&net, "Public IP", s.publicIP ?? "Looking up…")
        }
        sections.append((.network, net))

        // Assemble
        var result: [InfoLine] = []
        for (group, list) in sections where !list.isEmpty {
            if o.showSectionTitles {
                result.append(InfoLine(id: 0, kind: .section, label: "", value: group.rawValue))
            } else if !result.isEmpty {
                result.append(InfoLine(id: 0, kind: .spacer, label: "", value: ""))
            }
            result.append(contentsOf: list)
        }
        for index in result.indices { result[index].id = index }
        return result
    }

    /// Plain text for the clipboard.
    public static func plainText(_ lines: [InfoLine]) -> String {
        var out: [String] = []
        var lastLabel = ""
        for line in lines {
            switch line.kind {
            case .section:
                if !out.isEmpty { out.append("") }
                out.append(line.value.uppercased())
            case .subheader:
                out.append(line.value + ":")
            case .spacer:
                out.append("")
            case .row:
                if !line.label.isEmpty { lastLabel = line.label }
                let indent = lines.contains(where: { $0.kind == .subheader }) && isNetworkRow(line, in: lines) ? "  " : ""
                out.append("\(indent)\(line.label.isEmpty ? lastLabel : line.label): \(line.value)")
            }
        }
        return out.joined(separator: "\n")
    }

    private static func isNetworkRow(_ line: InfoLine, in lines: [InfoLine]) -> Bool {
        // A row belongs to an interface if a subheader appears before it with no section break between.
        var index = line.id - 1
        while index >= 0 && index < lines.count {
            switch lines[index].kind {
            case .subheader: return true
            case .section, .spacer: return false
            case .row: index -= 1
            }
        }
        return false
    }

    public static func json(_ snapshot: SystemSnapshot) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Individual values (for `nameplate --get` and Shortcuts)

    public static func values(for s: SystemSnapshot) -> [InfoValue] {
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
        add("gpu", "Graphics", s.gpus.map(gpuText).joined(separator: ", "))
        add("os", "macOS", osText(s.os))
        add("os-version", "macOS version", s.os.version)
        add("os-build", "macOS build", s.os.build)
        add("server", "Server version", s.serverVersion)
        add("user", "User", s.userName)
        add("user-full-name", "User full name", s.userFullName)
        add("uptime", "Uptime", uptimeText(s.uptimeSeconds))
        add("uptime-seconds", "Uptime (seconds)", String(s.uptimeSeconds))
        add("boot-time", "Boot time", ISO8601DateFormatter().string(from: s.bootTime))
        if let startup = s.volumes.first(where: \.isStartup) ?? s.volumes.first {
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
            add("\(iface.name).ip", "\(iface.displayName) IPv4", iface.ipv4.map(\.address).joined(separator: ", "))
            add("\(iface.name).ipv6", "\(iface.displayName) IPv6", iface.ipv6.filter { !$0.isLinkLocal }.map(\.address).joined(separator: ", "))
            add("\(iface.name).router", "\(iface.displayName) router", iface.router)
            add("\(iface.name).mac", "\(iface.displayName) MAC", iface.macAddress)
            add("\(iface.name).ssid", "\(iface.displayName) network", iface.wifi?.ssid)
        }
        return list
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
            if let startup = s.volumes.first(where: \.isStartup) { return [startup] }
            return Array(s.volumes.prefix(1))
        case .local:
            return s.volumes.filter(\.isLocal)
        case .all:
            return s.volumes
        }
    }
}
