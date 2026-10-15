import Foundation
import SystemConfiguration
import CoreWLAN

/// Reads the live network configuration from the System Configuration dynamic store,
/// the same source `scutil` uses. Covers DHCP, manual, multiple addresses, IPv6,
/// PPPoE and VPN services (built-in and third-party).
public enum NetworkCollector {

    public static func collect() -> NetworkInfo {
        let store = DynamicStore()
        let globalV4 = store.dictionary("State:/Network/Global/IPv4")
        let globalV6 = store.dictionary("State:/Network/Global/IPv6")
        let globalDNS = store.dictionary("State:/Network/Global/DNS")
        let primaryInterface = (globalV4?["PrimaryInterface"] as? String) ?? (globalV6?["PrimaryInterface"] as? String)
        let primaryService = (globalV4?["PrimaryService"] as? String) ?? (globalV6?["PrimaryService"] as? String)
        let serviceOrder = (store.dictionary("Setup:/Network/Global/IPv4")?["ServiceOrder"] as? [String]) ?? []

        // Every service that currently has an address, including VPNs that never appear in Setup.
        var serviceIDs: [String] = []
        for key in store.keys("State:/Network/Service/[^/]+/IPv4") + store.keys("State:/Network/Service/[^/]+/IPv6") {
            let parts = key.components(separatedBy: "/")
            if parts.count >= 5, !serviceIDs.contains(parts[3]) { serviceIDs.append(parts[3]) }
        }
        serviceIDs.sort { a, b in
            if a == primaryService { return true }
            if b == primaryService { return false }
            let ia = serviceOrder.firstIndex(of: a) ?? Int.max
            let ib = serviceOrder.firstIndex(of: b) ?? Int.max
            return ia != ib ? ia < ib : a < b
        }

        let macAddresses = LinkLayer.hardwareAddresses()
        let wifiNames = CWWiFiClient.interfaceNames() ?? []
        var interfaces: [InterfaceInfo] = []

        for sid in serviceIDs {
            let stateV4 = store.dictionary("State:/Network/Service/\(sid)/IPv4")
            let stateV6 = store.dictionary("State:/Network/Service/\(sid)/IPv6")
            let setupService = store.dictionary("Setup:/Network/Service/\(sid)")
            let setupInterface = store.dictionary("Setup:/Network/Service/\(sid)/Interface")
            let setupV4 = store.dictionary("Setup:/Network/Service/\(sid)/IPv4")
            let dhcp = store.dictionary("State:/Network/Service/\(sid)/DHCP")
            let dns = store.dictionary("State:/Network/Service/\(sid)/DNS")

            guard let bsdName = (stateV4?["InterfaceName"] as? String)
                    ?? (stateV6?["InterfaceName"] as? String)
                    ?? (setupInterface?["DeviceName"] as? String) else { continue }

            // IPv4
            let v4Addresses = stateV4?["Addresses"] as? [String] ?? []
            let masks = stateV4?["SubnetMasks"] as? [String] ?? []
            let ipv4 = v4Addresses.enumerated().map { (index, address) -> IPv4Address in
                let mask = index < masks.count ? masks[index] : nil
                return IPv4Address(address: address, subnetMask: mask, prefixLength: mask.flatMap(prefixLength(ofMask:)))
            }

            // IPv6
            let v6Addresses = stateV6?["Addresses"] as? [String] ?? []
            let v6Prefixes = stateV6?["PrefixLength"] as? [Int] ?? []
            let v6Flags = stateV6?["Flags"] as? [Int] ?? []
            let ipv6 = v6Addresses.enumerated().map { (index, address) -> IPv6Address in
                let flags = index < v6Flags.count ? v6Flags[index] : 0
                return IPv6Address(
                    address: address,
                    prefixLength: index < v6Prefixes.count ? v6Prefixes[index] : nil,
                    isLinkLocal: address.lowercased().hasPrefix("fe80"),
                    isTemporary: flags & 0x80 != 0 // IN6_IFF_TEMPORARY
                )
            }
            if ipv4.isEmpty && ipv6.allSatisfy(\.isLinkLocal) { continue }

            // What kind of interface is it?
            let hardware = setupInterface?["Hardware"] as? String
            let type = (setupInterface?["Type"] as? String) ?? ""
            let kind: InterfaceInfo.Kind
            if hardware == "AirPort" || wifiNames.contains(bsdName) {
                kind = .wifi
            } else if type == "PPP" || bsdName.hasPrefix("ppp") {
                kind = ((setupInterface?["SubType"] as? String) == "PPPoE") ? .ppp : .vpn
            } else if ["IPSec", "VPN", "L2TP", "PPTP"].contains(type)
                        || ["utun", "ipsec", "tun", "tap", "wg", "gif"].contains(where: { bsdName.hasPrefix($0) }) {
                kind = .vpn
            } else if bsdName.hasPrefix("bridge") {
                kind = .bridge
            } else if bsdName.hasPrefix("en") {
                kind = .ethernet
            } else {
                kind = .other
            }

            let serviceName = (setupService?["UserDefinedName"] as? String)
                ?? (setupInterface?["UserDefinedName"] as? String)
                ?? (stateV4?["UserDefinedName"] as? String)
            let displayName = serviceName ?? defaultName(for: kind)

            // How the address was assigned.
            var method = configMethodName(setupV4?["ConfigMethod"] as? String)
            if method == nil, dhcp != nil { method = "DHCP" }
            if method == nil, kind == .vpn, !ipv4.isEmpty { method = "VPN" }
            let dhcpServer = (dhcp?["Option_54"] as? Data).flatMap(ipv4String(fromData:))

            var info = InterfaceInfo(
                name: bsdName,
                displayName: displayName,
                kind: kind,
                isPrimary: bsdName == primaryInterface,
                macAddress: macAddresses[bsdName],
                ipv4: ipv4,
                router: stateV4?["Router"] as? String,
                configMethod: method,
                dhcpServer: dhcpServer,
                ipv6: ipv6,
                ipv6Router: stateV6?["Router"] as? String,
                dnsServers: dns?["ServerAddresses"] as? [String] ?? [],
                searchDomains: dns?["SearchDomains"] as? [String] ?? ((dns?["DomainName"] as? String).map { [$0] } ?? []),
                wifi: nil
            )
            if kind == .wifi { info.wifi = wifiDetails(interface: bsdName) }

            // Two services on one interface: merge rather than list it twice.
            if let existing = interfaces.firstIndex(where: { $0.name == bsdName }) {
                var merged = interfaces[existing]
                let known4 = merged.ipv4
                let known6 = merged.ipv6
                merged.ipv4.append(contentsOf: info.ipv4.filter { !known4.contains($0) })
                merged.ipv6.append(contentsOf: info.ipv6.filter { !known6.contains($0) })
                if merged.router == nil { merged.router = info.router }
                interfaces[existing] = merged
                continue
            }
            interfaces.append(info)
        }

        // The resolvers macOS is actually using (includes VPN-pushed and profile DNS).
        let dnsServers = globalDNS?["ServerAddresses"] as? [String] ?? []
        let searchDomains = globalDNS?["SearchDomains"] as? [String] ?? []

        // If the primary service had no DNS of its own, show the global resolvers there.
        if let index = interfaces.firstIndex(where: { $0.isPrimary }), interfaces[index].dnsServers.isEmpty {
            interfaces[index].dnsServers = dnsServers
            if interfaces[index].searchDomains.isEmpty { interfaces[index].searchDomains = searchDomains }
        }

        return NetworkInfo(primaryInterface: primaryInterface, interfaces: interfaces,
                           dnsServers: dnsServers, searchDomains: searchDomains)
    }

    // MARK: - Wi-Fi

    /// On macOS 14 and later the network name (SSID) is only available to apps the
    /// user has allowed to use Location Services. Without that it is simply left out.
    static func wifiDetails(interface name: String) -> WiFiInfo? {
        guard let iface = CWWiFiClient.shared().interface(withName: name) else { return nil }
        var info = WiFiInfo()
        if let ssid = iface.ssid(), !ssid.trimmingCharacters(in: .whitespaces).isEmpty { info.ssid = ssid }
        if let bssid = iface.bssid(), !bssid.isEmpty { info.bssid = bssid }
        let rssi = iface.rssiValue()
        if rssi != 0 { info.rssi = rssi }
        let noise = iface.noiseMeasurement()
        if noise != 0 { info.noise = noise }
        if let channel = iface.wlanChannel() {
            info.channel = channel.channelNumber
            switch channel.channelBand.rawValue {
            case 1: info.band = "2.4 GHz"
            case 2: info.band = "5 GHz"
            case 3: info.band = "6 GHz"
            default: break
            }
        }
        let rate = iface.transmitRate()
        if rate > 0 { info.transmitRateMbps = rate }
        return info
    }

    // MARK: - Helpers

    static func defaultName(for kind: InterfaceInfo.Kind) -> String {
        switch kind {
        case .wifi: return "Wi-Fi"
        case .ethernet: return "Ethernet"
        case .vpn: return "VPN"
        case .ppp: return "PPPoE"
        case .bridge: return "Bridge"
        case .other: return "Network"
        }
    }

    static func configMethodName(_ raw: String?) -> String? {
        switch raw {
        case "DHCP": return "DHCP"
        case "INFORM": return "DHCP with manual address"
        case "Manual": return "Manual"
        case "BOOTP": return "BOOTP"
        case "LinkLocal": return "Link-local only"
        case "PPP": return "PPP"
        case "Automatic": return "Automatic"
        case nil, "Off": return nil
        default: return raw
        }
    }

    static func prefixLength(ofMask mask: String) -> Int? {
        let octets = mask.split(separator: ".").compactMap { UInt8($0) }
        guard octets.count == 4 else { return nil }
        return octets.reduce(0) { $0 + $1.nonzeroBitCount }
    }

    static func ipv4String(fromData data: Data) -> String? {
        guard data.count == 4 else { return nil }
        return data.map { String($0) }.joined(separator: ".")
    }
}

/// A read-only handle on the System Configuration dynamic store.
struct DynamicStore {
    let store: SCDynamicStore?

    init() {
        store = SCDynamicStoreCreate(nil, "Nameplate" as CFString, nil, nil)
    }

    func dictionary(_ key: String) -> [String: Any]? {
        guard let store, let value = SCDynamicStoreCopyValue(store, key as CFString) else { return nil }
        return value as? [String: Any]
    }

    func keys(_ pattern: String) -> [String] {
        guard let store, let list = SCDynamicStoreCopyKeyList(store, pattern as CFString) else { return [] }
        return (list as NSArray) as? [String] ?? []
    }
}
