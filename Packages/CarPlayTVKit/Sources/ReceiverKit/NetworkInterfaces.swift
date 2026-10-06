import Foundation

public enum NetworkInterfaces {
    /// The IPv4 address of the Wi-Fi interface (en0), falling back to any other
    /// non-loopback IPv4 address.
    public static func localIPv4Address() -> String? {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return nil }
        defer { freeifaddrs(pointer) }

        var fallback: String?
        for interface in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard let address = interface.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else { continue }
            let flags = Int32(interface.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(cString: host)
            let name = String(cString: interface.pointee.ifa_name)
            if name == "en0" { return ip }
            if fallback == nil, name.hasPrefix("en") || name.hasPrefix("bridge") { fallback = ip }
        }
        return fallback
    }
}
