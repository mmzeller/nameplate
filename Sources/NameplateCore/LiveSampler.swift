import Foundation
import IOKit
import IOKit.ps

/// Which live numbers to sample.
public struct LiveNeeds: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let cpu = LiveNeeds(rawValue: 1 << 0)
    public static let memory = LiveNeeds(rawValue: 1 << 1)
    public static let battery = LiveNeeds(rawValue: 1 << 2)
    public static let network = LiveNeeds(rawValue: 1 << 3)
    /// Not sampled; means "redraw when the minute changes" for {time} and {date}.
    public static let clock = LiveNeeds(rawValue: 1 << 4)

    public static let sampled: LiveNeeds = [.cpu, .memory, .battery, .network]
}

/// Samples CPU, memory, battery and network traffic. CPU and traffic are rates, so they
/// come from the difference between two calls; the first call returns nil for them.
/// Call from one thread at a time.
public final class LiveSampler: @unchecked Sendable {
    private let host = mach_host_self()
    private var lastTicks: (UInt32, UInt32, UInt32, UInt32)?
    private var lastNet: (name: String, inBytes: UInt32, outBytes: UInt32, time: TimeInterval)?

    public init() {}

    public func sample(_ needs: LiveNeeds, primaryInterface: String?) -> LiveStats {
        var stats = LiveStats()
        if needs.contains(.cpu) { stats.cpuUsage = cpuUsage() }
        if needs.contains(.memory) { memory(into: &stats) }
        if needs.contains(.battery) { stats.battery = LiveSampler.battery() }
        if needs.contains(.network) { network(primaryInterface, into: &stats) }
        return stats
    }

    // MARK: CPU

    private func cpuUsage() -> Double? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let capacity = Int(count)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: capacity) { raw in
                host_statistics(host, HOST_CPU_LOAD_INFO, raw, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let ticks = info.cpu_ticks
        defer { lastTicks = ticks }
        guard let last = lastTicks else { return nil }
        // The counters are 32-bit and wrap on long uptimes, so subtract with wrapping.
        let user = Double(ticks.0 &- last.0)
        let system = Double(ticks.1 &- last.1)
        let idle = Double(ticks.2 &- last.2)
        let nice = Double(ticks.3 &- last.3)
        let total = user + system + idle + nice
        guard total > 0 else { return nil }
        return min(max((user + system + nice) / total, 0), 1)
    }

    // MARK: Memory

    private func memory(into stats: inout LiveStats) {
        let total = ProcessInfo.processInfo.physicalMemory
        stats.memoryTotal = total
        var vm = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let capacity = Int(count)
        let result = withUnsafeMutablePointer(to: &vm) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: capacity) { raw in
                host_statistics64(host, HOST_VM_INFO64, raw, &count)
            }
        }
        if result == KERN_SUCCESS {
            // Same sum Activity Monitor calls "Memory Used": app memory + wired + compressed.
            let page = UInt64(Sysctl.int("hw.pagesize") ?? 4096)
            let internalPages = UInt64(vm.internal_page_count)
            let purgeable = UInt64(vm.purgeable_count)
            let appPages = internalPages > purgeable ? internalPages - purgeable : 0
            let used = (appPages + UInt64(vm.wire_count) + UInt64(vm.compressor_page_count)) * page
            stats.memoryUsed = min(used, total)
        }
        switch Sysctl.int("kern.memorystatus_vm_pressure_level") {
        case .some(2): stats.memoryPressure = .warning
        case .some(4): stats.memoryPressure = .critical
        case .some: stats.memoryPressure = .normal
        case .none: break
        }
    }

    // MARK: Battery

    static func battery() -> BatteryInfo? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() else { return nil }
        for source in (list as NSArray) as [AnyObject] {
            guard let rawDescription = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue(),
                  let info = (rawDescription as NSDictionary) as? [String: Any],
                  (info[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }

            let current = info[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maximum = max(info[kIOPSMaxCapacityKey] as? Int ?? 100, 1)
            let state = info[kIOPSPowerSourceStateKey] as? String
            let toEmpty = info[kIOPSTimeToEmptyKey] as? Int
            let toFull = info[kIOPSTimeToFullChargeKey] as? Int
            var battery = BatteryInfo(
                percent: min(100, Int((Double(current) / Double(maximum) * 100).rounded())),
                isCharging: info[kIOPSIsChargingKey] as? Bool ?? false,
                isOnPower: state == kIOPSACPowerValue,
                isCharged: info[kIOPSIsChargedKey] as? Bool ?? false,
                minutesToEmpty: (toEmpty ?? 0) > 0 ? toEmpty : nil,
                minutesToFull: (toFull ?? 0) > 0 ? toFull : nil,
                cycleCount: nil,
                healthPercent: nil
            )
            addHealth(to: &battery)
            return battery
        }
        return nil
    }

    private static func addHealth(to battery: inout BatteryInfo) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceNameMatching("AppleSmartBattery"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        func number(_ key: String) -> Int? {
            let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
            return (value as? NSNumber)?.intValue
        }
        battery.cycleCount = number("CycleCount")
        // Apple silicon reports MaxCapacity as a percentage; the real figure is AppleRawMaxCapacity.
        var fullCharge = number("AppleRawMaxCapacity")
        if fullCharge == nil, let max = number("MaxCapacity"), max > 100 { fullCharge = max }
        if let fullCharge, let design = number("DesignCapacity"), design > 0 {
            battery.healthPercent = min(100, Int((Double(fullCharge) / Double(design) * 100).rounded()))
        }
    }

    // MARK: Network traffic

    private func network(_ name: String?, into stats: inout LiveStats) {
        guard let name, let counters = LiveSampler.byteCounters(for: name) else {
            lastNet = nil
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        defer { lastNet = (name: name, inBytes: counters.inBytes, outBytes: counters.outBytes, time: now) }
        guard let last = lastNet, last.name == name, now > last.time else { return }
        let elapsed = now - last.time
        // 32-bit counters: wrapping subtraction handles the rollover.
        stats.downBytesPerSecond = Double(counters.inBytes &- last.inBytes) / elapsed
        stats.upBytesPerSecond = Double(counters.outBytes &- last.outBytes) / elapsed
    }

    static func byteCounters(for name: String) -> (inBytes: UInt32, outBytes: UInt32)? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            cursor = entry.pointee.ifa_next
            guard let address = entry.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_LINK),
                  let rawName = entry.pointee.ifa_name,
                  String(cString: rawName) == name,
                  let data = entry.pointee.ifa_data else { continue }
            let counters = data.assumingMemoryBound(to: if_data.self).pointee
            return (inBytes: counters.ifi_ibytes, outBytes: counters.ifi_obytes)
        }
        return nil
    }
}
