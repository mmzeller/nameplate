import Foundation

public enum NameplateInfo {
    public static let version = "1.1.4"
    public static let bundleIdentifier = "com.mmzeller.Nameplate"
}

/// Everything Nameplate knows about the Mac at one moment.
public struct SystemSnapshot: Codable, Equatable, Sendable {
    // Hardware
    public var computerName: String
    public var localHostName: String?
    public var hostName: String?
    public var model: String
    public var modelIdentifier: String
    public var serialNumber: String?
    public var hardwareUUID: String?
    public var chip: String
    public var isAppleSilicon: Bool
    public var cpuCores: CoreCounts
    public var memoryBytes: UInt64
    public var gpus: [GPUInfo]

    // Status
    public var os: OSInfo
    public var serverVersion: String?
    public var userName: String
    public var userFullName: String
    public var bootTime: Date
    public var uptimeSeconds: Int
    public var volumes: [VolumeInfo]

    // Network
    public var network: NetworkInfo
    public var publicIP: String?

    public var collectedAt: Date
}

public struct CoreCounts: Codable, Equatable, Sendable {
    public var total: Int
    public var threads: Int?
    public var performance: Int?
    public var efficiency: Int?
}

public struct GPUInfo: Codable, Equatable, Sendable {
    public var name: String
    public var cores: Int?
}

public struct OSInfo: Codable, Equatable, Sendable {
    /// e.g. "macOS Tahoe"
    public var name: String
    /// e.g. "26.0.1"
    public var version: String
    /// e.g. "25A362"
    public var build: String
}

public struct VolumeInfo: Codable, Equatable, Sendable {
    public var name: String
    public var mountPoint: String
    public var totalBytes: Int64
    public var availableBytes: Int64
    public var isStartup: Bool
    public var isLocal: Bool
    public var isInternal: Bool?
    public var isRemovable: Bool?

    public var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(totalBytes - availableBytes) / Double(totalBytes)
    }
}

public struct NetworkInfo: Codable, Equatable, Sendable {
    public var primaryInterface: String?
    public var interfaces: [InterfaceInfo]
    /// The resolvers macOS is actually using right now.
    public var dnsServers: [String]
    public var searchDomains: [String]

    public var primary: InterfaceInfo? {
        interfaces.first(where: { $0.isPrimary }) ?? interfaces.first
    }
}

public struct InterfaceInfo: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case wifi, ethernet, vpn, ppp, bridge, other
    }

    /// BSD name, e.g. "en0"
    public var name: String
    /// Network service name, e.g. "Wi-Fi"
    public var displayName: String
    public var kind: Kind
    public var isPrimary: Bool
    public var macAddress: String?
    public var ipv4: [IPv4Address]
    public var router: String?
    public var configMethod: String?
    public var dhcpServer: String?
    public var ipv6: [IPv6Address]
    public var ipv6Router: String?
    public var dnsServers: [String]
    public var searchDomains: [String]
    public var wifi: WiFiInfo?
}

public struct IPv4Address: Codable, Equatable, Sendable {
    public var address: String
    public var subnetMask: String?
    public var prefixLength: Int?
}

public struct IPv6Address: Codable, Equatable, Sendable {
    public var address: String
    public var prefixLength: Int?
    public var isLinkLocal: Bool
    public var isTemporary: Bool
}

public struct WiFiInfo: Codable, Equatable, Sendable {
    public var ssid: String?
    public var bssid: String?
    public var rssi: Int?
    public var noise: Int?
    public var channel: Int?
    public var band: String?
    public var transmitRateMbps: Double?

    public init() {}
}

// MARK: - Live numbers

public enum MemoryPressure: String, Codable, Sendable {
    case normal, warning, critical
    public var title: String { rawValue.capitalized }
}

public struct BatteryInfo: Codable, Equatable, Sendable {
    public var percent: Int
    public var isCharging: Bool
    public var isOnPower: Bool
    public var isCharged: Bool
    public var minutesToEmpty: Int?
    public var minutesToFull: Int?
    public var cycleCount: Int?
    public var healthPercent: Int?
}

/// Numbers that change from second to second. Sampled separately from `SystemSnapshot`.
public struct LiveStats: Codable, Equatable, Sendable {
    /// 0...1 across all cores.
    public var cpuUsage: Double?
    public var memoryUsed: UInt64?
    public var memoryTotal: UInt64?
    public var memoryPressure: MemoryPressure?
    public var battery: BatteryInfo?
    public var downBytesPerSecond: Double?
    public var upBytesPerSecond: Double?

    public init() {}
}
