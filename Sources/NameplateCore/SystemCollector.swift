import Foundation
import Metal
import SystemConfiguration

/// Collects a `SystemSnapshot`. Safe to call from any thread.
public enum SystemCollector {

    /// - Parameter previous: a prior snapshot whose hardware details can be reused
    ///   (model, serial, chip, memory and graphics never change while the Mac is running).
    public static func collect(reusingHardwareFrom previous: SystemSnapshot? = nil) -> SystemSnapshot {
        let hardware = previous.map(Hardware.init(snapshot:)) ?? Hardware.read()
        let boot = Sysctl.bootTime() ?? Date(timeIntervalSinceNow: -ProcessInfo.processInfo.systemUptime)
        let now = Date()

        return SystemSnapshot(
            computerName: computerName(),
            localHostName: localHostName(),
            hostName: unixHostName(),
            model: hardware.model,
            modelIdentifier: hardware.modelIdentifier,
            serialNumber: hardware.serialNumber,
            hardwareUUID: hardware.hardwareUUID,
            chip: hardware.chip,
            isAppleSilicon: hardware.isAppleSilicon,
            cpuCores: hardware.cores,
            memoryBytes: ProcessInfo.processInfo.physicalMemory,
            gpus: hardware.gpus,
            os: osInfo(),
            serverVersion: serverVersion(),
            userName: NSUserName(),
            userFullName: NSFullUserName(),
            bootTime: boot,
            uptimeSeconds: max(0, Int(now.timeIntervalSince(boot))),
            volumes: VolumeCollector.collect(),
            network: NetworkCollector.collect(),
            publicIP: previous?.publicIP,
            collectedAt: now
        )
    }

    // MARK: - Names

    static func computerName() -> String {
        if let name = SCDynamicStoreCopyComputerName(nil, nil) {
            let value = name as String
            if !value.isEmpty { return value }
        }
        return localHostName()?.replacingOccurrences(of: ".local", with: "") ?? "Mac"
    }

    static func localHostName() -> String? {
        guard let name = SCDynamicStoreCopyLocalHostName(nil) else { return nil }
        let value = name as String
        return value.isEmpty ? nil : value + ".local"
    }

    static func unixHostName() -> String? {
        let capacity = 256
        var buffer = [CChar](repeating: 0, count: capacity)
        guard gethostname(&buffer, capacity - 1) == 0 else { return nil }
        let value = buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        return value.isEmpty ? nil : value
    }

    // MARK: - Operating system

    static func osInfo() -> OSInfo {
        // The kernel reports the real version. ProcessInfo can report a compatibility
        // number (e.g. 16.0 on macOS 26) when the app was built with an older SDK.
        let v = ProcessInfo.processInfo.operatingSystemVersion
        var fallback = "\(v.majorVersion).\(v.minorVersion)"
        if v.patchVersion > 0 { fallback += ".\(v.patchVersion)" }
        var version = Sysctl.string("kern.osproductversion") ?? fallback
        let major = Int(version.split(separator: ".").first ?? "") ?? v.majorVersion
        // Rapid Security Response / Background Security Improvement suffix, like "(a)".
        if let extra = Sysctl.string("kern.osproductversionextra"), !extra.isEmpty, !version.contains(extra) {
            version += " \(extra)"
        }
        let build = Sysctl.string("kern.osversion") ?? ""
        let names: [Int: String] = [
            11: "Big Sur", 12: "Monterey", 13: "Ventura", 14: "Sonoma", 15: "Sequoia", 26: "Tahoe",
        ]
        let name = names[major].map { "macOS \($0)" } ?? "macOS"
        return OSInfo(name: name, version: version, build: build)
    }

    static func serverVersion() -> String? {
        guard let bundle = Bundle(path: "/Applications/Server.app") else { return nil }
        return bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }
}

// MARK: - Hardware

struct Hardware {
    var model: String
    var modelIdentifier: String
    var serialNumber: String?
    var hardwareUUID: String?
    var chip: String
    var isAppleSilicon: Bool
    var cores: CoreCounts
    var gpus: [GPUInfo]

    init(snapshot s: SystemSnapshot) {
        model = s.model
        modelIdentifier = s.modelIdentifier
        serialNumber = s.serialNumber
        hardwareUUID = s.hardwareUUID
        chip = s.chip
        isAppleSilicon = s.isAppleSilicon
        cores = s.cpuCores
        gpus = s.gpus
    }

    init(model: String, modelIdentifier: String, serialNumber: String?, hardwareUUID: String?,
         chip: String, isAppleSilicon: Bool, cores: CoreCounts, gpus: [GPUInfo]) {
        self.model = model
        self.modelIdentifier = modelIdentifier
        self.serialNumber = serialNumber
        self.hardwareUUID = hardwareUUID
        self.chip = chip
        self.isAppleSilicon = isAppleSilicon
        self.cores = cores
        self.gpus = gpus
    }

    static func read() -> Hardware {
        let serial = IORegistry.string(IORegistry.platformProperty("IOPlatformSerialNumber"))
        let uuid = IORegistry.string(IORegistry.platformProperty("IOPlatformUUID"))
        let identifier = Sysctl.string("hw.model")
            ?? IORegistry.string(IORegistry.platformProperty("model"))
            ?? "Mac"

        let rawChip = Sysctl.string("machdep.cpu.brand_string") ?? "Unknown processor"
        let appleSilicon = rawChip.hasPrefix("Apple") || Sysctl.int("hw.optional.arm64") == 1

        var cores = CoreCounts(total: Sysctl.int("hw.physicalcpu") ?? ProcessInfo.processInfo.processorCount,
                               threads: nil, performance: nil, efficiency: nil)
        let logical = Sysctl.int("hw.logicalcpu") ?? cores.total
        if logical != cores.total { cores.threads = logical }
        if (Sysctl.int("hw.nperflevels") ?? 1) >= 2 {
            cores.performance = Sysctl.int("hw.perflevel0.physicalcpu")
            cores.efficiency = Sysctl.int("hw.perflevel1.physicalcpu")
        }

        return Hardware(
            model: modelName(identifier: identifier, serial: serial),
            modelIdentifier: identifier,
            serialNumber: serial,
            hardwareUUID: uuid,
            chip: cleanVendorString(rawChip),
            isAppleSilicon: appleSilicon,
            cores: cores,
            gpus: graphics()
        )
    }

    /// The marketing name, e.g. "MacBook Pro (14-inch, Nov 2023)".
    static func modelName(identifier: String, serial: String?) -> String {
        // Apple silicon keeps the marketing name in the device tree.
        if let name = IORegistry.string(IORegistry.property(atPath: "IODeviceTree:/product", key: "product-name")) {
            return name
        }
        // Intel: the name About This Mac cached, keyed by the end of the serial number.
        if let names = CFPreferencesCopyAppValue("CPU Names" as CFString, "com.apple.SystemProfiler" as CFString) as? [String: String],
           !names.isEmpty {
            if let serial, serial.count >= 3 {
                for length in [4, 3] where serial.count >= length {
                    let suffix = String(serial.suffix(length)) + "-"
                    if let match = names.first(where: { $0.key.hasPrefix(suffix) }) { return match.value }
                }
            }
            if names.count == 1, let only = names.values.first { return only }
        }
        // Intel: the table macOS ships for Server Information.
        let base = "/System/Library/PrivateFrameworks/ServerInformation.framework/Versions/A/Resources/"
        for folder in ["en.lproj", "English.lproj", "Base.lproj"] {
            guard let table = NSDictionary(contentsOfFile: base + folder + "/SIMachineAttributes.plist") as? [String: Any],
                  let entry = table[identifier] as? [String: Any],
                  let localizable = entry["_LOCALIZABLE_"] as? [String: Any],
                  let name = localizable["marketingModel"] as? String,
                  !name.isEmpty else { continue }
            return name
        }
        return familyName(identifier)
    }

    static func familyName(_ identifier: String) -> String {
        let families: [(String, String)] = [
            ("MacBookPro", "MacBook Pro"), ("MacBookAir", "MacBook Air"), ("MacBook", "MacBook"),
            ("iMacPro", "iMac Pro"), ("iMac", "iMac"), ("Macmini", "Mac mini"), ("MacPro", "Mac Pro"),
            ("VirtualMac", "Virtual Mac"), ("Mac", "Mac"),
        ]
        for (prefix, name) in families where identifier.hasPrefix(prefix) { return name }
        return identifier
    }

    static func graphics() -> [GPUInfo] {
        var names: [String] = []
        for device in MTLCopyAllDevices() {
            let name = cleanVendorString(device.name)
            if !names.contains(name) { names.append(name) }
        }
        let coreCounts = IORegistry.gpuCoreCounts()
        return names.enumerated().map { index, name in
            GPUInfo(name: name, cores: names.count == coreCounts.count ? coreCounts[index] : (names.count == 1 ? coreCounts.first : nil))
        }
    }

    /// "Intel(R) Core(TM) i9-9880H CPU @ 2.30GHz" → "Intel Core i9-9880H @ 2.30GHz"
    static func cleanVendorString(_ value: String) -> String {
        var s = value
        for junk in ["(R)", "(r)", "(TM)", "(tm)", "®", "™"] {
            s = s.replacingOccurrences(of: junk, with: "")
        }
        s = s.replacingOccurrences(of: " CPU ", with: " ")
        while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
        return s.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Disks

enum VolumeCollector {
    static func collect() -> [VolumeInfo] {
        let keys: [URLResourceKey] = [
            .volumeNameKey, .volumeLocalizedNameKey, .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
            .volumeIsRootFileSystemKey, .volumeIsInternalKey, .volumeIsRemovableKey,
            .volumeIsLocalKey, .volumeIsBrowsableKey,
        ]
        guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) else {
            return []
        }
        var volumes: [VolumeInfo] = []
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if values.volumeIsBrowsable == false { continue }
            let total = Int64(values.volumeTotalCapacity ?? 0)
            guard total > 0 else { continue }
            var available = values.volumeAvailableCapacityForImportantUsage ?? 0
            if available <= 0 { available = Int64(values.volumeAvailableCapacity ?? 0) }
            let isStartup = values.volumeIsRootFileSystem ?? (url.path == "/")
            volumes.append(VolumeInfo(
                name: values.volumeLocalizedName ?? values.volumeName ?? url.lastPathComponent,
                mountPoint: url.path,
                totalBytes: total,
                availableBytes: min(max(available, 0), total),
                isStartup: isStartup,
                isLocal: values.volumeIsLocal ?? true,
                isInternal: values.volumeIsInternal,
                isRemovable: values.volumeIsRemovable
            ))
        }
        return volumes.sorted { a, b in
            if a.isStartup != b.isStartup { return a.isStartup }
            if (a.isInternal ?? false) != (b.isInternal ?? false) { return a.isInternal ?? false }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
}
