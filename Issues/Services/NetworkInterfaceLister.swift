import Foundation

#if os(macOS)
import Darwin

/// Enumerates the host's non-loopback IPv4 / IPv6 addresses across active
/// interfaces (#0083). Used by `RemoteHostController` to populate the
/// "Reachable on this Mac at" list in the settings sheet.
///
/// Pure C-API wrapper around `getifaddrs(3)`. Doesn't touch `Network.framework`
/// because `NWInterface` doesn't expose the actual bound addresses — only
/// the interface type and name. That's fine for the WiFi/Wired/Tailscale
/// path discrimination but not for "what `curl` should target."
enum NetworkInterfaceLister {

    struct InterfaceAddress: Equatable, Identifiable {
        var id: String { "\(name)|\(address)" }
        /// Interface name, e.g. `en0`, `utun5`. Useful for the row label
        /// ("Tailscale" is `utun*`).
        let name: String
        /// IPv4 dotted-quad or IPv6 textual form. IPv6 may include a
        /// `%scope` suffix for link-local addresses.
        let address: String
        let family: Family

        enum Family: Equatable {
            case ipv4
            case ipv6
        }
    }

    /// Returns the up, non-loopback addresses currently bound to any
    /// interface, in a stable order (IPv4 before IPv6, then alphabetical
    /// by interface name).
    static func current() -> [InterfaceAddress] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }

        var results: [InterfaceAddress] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            let flags = entry.pointee.ifa_flags
            if (flags & UInt32(IFF_UP)) == 0 { continue }
            if (flags & UInt32(IFF_LOOPBACK)) != 0 { continue }
            guard let addrPtr = entry.pointee.ifa_addr else { continue }
            let family = addrPtr.pointee.sa_family
            let nameCStr = entry.pointee.ifa_name
            let name = nameCStr.map { String(cString: $0) } ?? "?"

            if family == sa_family_t(AF_INET) {
                if let address = string(from: addrPtr, length: socklen_t(MemoryLayout<sockaddr_in>.size)) {
                    results.append(InterfaceAddress(name: name, address: address, family: .ipv4))
                }
            } else if family == sa_family_t(AF_INET6) {
                if let address = string(from: addrPtr, length: socklen_t(MemoryLayout<sockaddr_in6>.size)) {
                    results.append(InterfaceAddress(name: name, address: address, family: .ipv6))
                }
            }
        }

        results.sort { a, b in
            if a.family != b.family {
                return a.family == .ipv4
            }
            return a.name < b.name
        }
        return results
    }

    private static func string(from addr: UnsafePointer<sockaddr>, length: socklen_t) -> String? {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = getnameinfo(
            addr,
            length,
            &host,
            socklen_t(host.count),
            nil,
            0,
            NI_NUMERICHOST
        )
        guard result == 0 else { return nil }
        return String(cString: host)
    }
}

#endif
