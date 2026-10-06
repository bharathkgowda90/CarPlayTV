import Foundation

/// SSDP (UPnP discovery) message formatting and parsing.
public enum SSDP {
    public static let multicastHost = "239.255.255.250"
    public static let port: UInt16 = 1900
    static let server = "iOS UPnP/1.0 CarPlayTV/1.0"

    /// Notification types we advertise, paired with their USN.
    public static func targets(udn: String) -> [(nt: String, usn: String)] {
        let uuid = "uuid:\(udn)"
        return [
            ("upnp:rootdevice", "\(uuid)::upnp:rootdevice"),
            (uuid, uuid),
            (UPnPDocuments.deviceType, "\(uuid)::\(UPnPDocuments.deviceType)"),
            (UPnPDocuments.avTransport, "\(uuid)::\(UPnPDocuments.avTransport)"),
            (UPnPDocuments.renderingControl, "\(uuid)::\(UPnPDocuments.renderingControl)"),
            (UPnPDocuments.connectionManager, "\(uuid)::\(UPnPDocuments.connectionManager)"),
        ]
    }

    public static func notify(nt: String, usn: String, location: String, alive: Bool) -> String {
        var lines = [
            "NOTIFY * HTTP/1.1",
            "HOST: \(multicastHost):\(port)",
            "NT: \(nt)",
            "NTS: \(alive ? "ssdp:alive" : "ssdp:byebye")",
            "USN: \(usn)",
        ]
        if alive {
            lines += ["CACHE-CONTROL: max-age=1800", "LOCATION: \(location)", "SERVER: \(server)"]
        }
        return lines.joined(separator: "\r\n") + "\r\n\r\n"
    }

    public static func searchResponse(st: String, usn: String, location: String, date: Date = Date()) -> String {
        [
            "HTTP/1.1 200 OK",
            "CACHE-CONTROL: max-age=1800",
            "DATE: \(httpDate(date))",
            "EXT:",
            "LOCATION: \(location)",
            "SERVER: \(server)",
            "ST: \(st)",
            "USN: \(usn)",
        ].joined(separator: "\r\n") + "\r\n\r\n"
    }

    /// Returns the search target if `message` is an M-SEARCH discovery request.
    public static func searchTarget(in message: String) -> String? {
        let lines = message.components(separatedBy: "\r\n")
        guard let first = lines.first, first.uppercased().hasPrefix("M-SEARCH") else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).uppercased()
            headers[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        guard headers["MAN"]?.contains("ssdp:discover") == true else { return nil }
        return headers["ST"]
    }

    /// Responses to send for a search target (`ssdp:all` answers with everything).
    public static func responses(for st: String, udn: String, location: String) -> [String] {
        targets(udn: udn)
            .filter { st == "ssdp:all" || st == $0.nt }
            .map { searchResponse(st: $0.nt, usn: $0.usn, location: location) }
    }

    static func httpDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter.string(from: date)
    }
}
