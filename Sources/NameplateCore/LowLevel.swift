import Foundation
import IOKit

/// Small wrappers around sysctl.
enum Sysctl {
    static func string(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size + 1)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let value = buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func int(_ name: String) -> Int? {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        if size == MemoryLayout<Int32>.size {
            return Int(Int32(truncatingIfNeeded: value))
        }
        return Int(value)
    }

    static func bootTime() -> Date? {
        var tv = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &tv, &size, nil, 0) == 0, tv.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: Double(tv.tv_sec) + Double(tv.tv_usec) / 1_000_000)
    }
}

/// Small wrappers around the I/O Registry.
enum IORegistry {
    static func platformProperty(_ key: String) -> AnyObject? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    static func property(atPath path: String, key: String) -> AnyObject? {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, path)
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        return IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    /// Reads a property that may be stored as a string or as NUL-terminated data.
    static func string(_ value: AnyObject?) -> String? {
        var text: String?
        if let string = value as? String {
            text = string
        } else if let data = value as? Data {
            text = String(decoding: data.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// GPU core counts reported by each graphics accelerator (Apple silicon only).
    static func gpuCoreCounts() -> [Int] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }
        var counts: [Int] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let value = IORegistryEntryCreateCFProperty(service, "gpu-core-count" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
               let number = value as? NSNumber {
                counts.append(number.intValue)
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return counts
    }
}

/// MAC addresses for every interface, keyed by BSD name.
enum LinkLayer {
    static func hardwareAddresses() -> [String: String] {
        var result: [String: String] = [:]
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return result }
        defer { freeifaddrs(list) }

        let dataOffset = MemoryLayout<sockaddr_dl>.offset(of: \sockaddr_dl.sdl_data) ?? 8
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            guard let address = entry.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_LINK),
                  let rawName = entry.pointee.ifa_name else { continue }
            let name = String(cString: rawName)
            let raw = UnsafeRawPointer(address)
            let nameLength = Int(raw.load(fromByteOffset: 5, as: UInt8.self))   // sdl_nlen
            let addressLength = Int(raw.load(fromByteOffset: 6, as: UInt8.self)) // sdl_alen
            guard addressLength == 6 else { continue }
            var bytes: [UInt8] = []
            for i in 0..<addressLength {
                bytes.append(raw.load(fromByteOffset: dataOffset + nameLength + i, as: UInt8.self))
            }
            guard bytes.contains(where: { $0 != 0 }) else { continue }
            result[name] = bytes.map { String(format: "%02x", $0) }.joined(separator: ":")
        }
        return result
    }
}
