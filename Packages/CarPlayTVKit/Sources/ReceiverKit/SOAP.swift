import Foundation

/// A parsed SOAP action call.
public struct SOAPRequest: Equatable, Sendable {
    public let action: String
    public let arguments: [String: String]
}

public enum SOAP {
    /// Parses the action name and its arguments from a SOAP envelope.
    public static func parse(_ body: Data) -> SOAPRequest? {
        let delegate = ParserDelegate()
        let parser = XMLParser(data: body)
        parser.shouldProcessNamespaces = true
        parser.delegate = delegate
        guard parser.parse(), let action = delegate.action else { return nil }
        return SOAPRequest(action: action, arguments: delegate.arguments)
    }

    public static func response(action: String, serviceType: String, values: [(String, String)]) -> Data {
        let arguments = values.map { "<\($0.0)>\(XMLText.escape($0.1))</\($0.0)>" }.joined()
        return Data("""
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body><u:\(action)Response xmlns:u="\(serviceType)">\(arguments)</u:\(action)Response></s:Body></s:Envelope>
        """.utf8)
    }

    public static func fault(code: Int, description: String) -> Data {
        Data("""
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body><s:Fault><faultcode>s:Client</faultcode><faultstring>UPnPError</faultstring><detail><UPnPError xmlns="urn:schemas-upnp-org:control-1-0"><errorCode>\(code)</errorCode><errorDescription>\(XMLText.escape(description))</errorDescription></UPnPError></detail></s:Fault></s:Body></s:Envelope>
        """.utf8)
    }

    private final class ParserDelegate: NSObject, XMLParserDelegate {
        var action: String?
        var arguments: [String: String] = [:]
        private var inBody = false
        private var depthInAction = 0
        private var currentArgument: String?
        private var text = ""

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            if !inBody {
                if elementName == "Body" { inBody = true }
                return
            }
            if action == nil {
                action = elementName
                depthInAction = 1
                return
            }
            depthInAction += 1
            if depthInAction == 2 {
                currentArgument = elementName
                text = ""
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if currentArgument != nil { text += string }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
            guard action != nil else { return }
            if depthInAction == 2, let argument = currentArgument {
                arguments[argument] = text
                currentArgument = nil
            }
            depthInAction -= 1
        }
    }
}

/// Reads the title from DIDL-Lite metadata sent with SetAVTransportURI.
public enum DIDLLite {
    public static func title(from metadata: String?) -> String? {
        guard let metadata, let start = metadata.range(of: "<dc:title>"),
              let end = metadata.range(of: "</dc:title>", range: start.upperBound..<metadata.endIndex) else { return nil }
        let raw = String(metadata[start.upperBound..<end.lowerBound])
        let decoded = raw.replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return decoded.isEmpty ? nil : decoded
    }
}
