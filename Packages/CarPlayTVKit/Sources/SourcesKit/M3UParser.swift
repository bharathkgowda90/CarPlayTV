import Foundation

public enum M3UParserError: Error, Equatable {
    case empty
    case noEntries
}

/// Parses M3U / M3U8 (extended) playlists as used by IPTV providers.
public struct M3UParser: Sendable {
    /// Merge entries with the same name and group into one channel with several lines.
    public var mergeDuplicates: Bool

    public init(mergeDuplicates: Bool = true) {
        self.mergeDuplicates = mergeDuplicates
    }

    public func parse(_ text: String) throws -> [Channel] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw M3UParserError.empty }

        var channels: [Channel] = []
        var indexByKey: [String: Int] = [:]
        var pending: PendingEntry?

        for rawLine in text.split(whereSeparator: \.isNewline) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("\u{FEFF}") { line.removeFirst() }
            if line.isEmpty { continue }

            if line.hasPrefix("#EXTINF") {
                pending = Self.parseExtInf(line)
                continue
            }
            if line.hasPrefix("#EXTGRP:") {
                if pending?.group == nil {
                    pending?.group = String(line.dropFirst("#EXTGRP:".count)).trimmingCharacters(in: .whitespaces)
                }
                continue
            }
            if line.hasPrefix("#") { continue }

            guard let url = Self.makeURL(line) else {
                pending = nil
                continue
            }
            let entry = pending ?? PendingEntry(name: url.lastPathComponent.isEmpty ? url.absoluteString : url.lastPathComponent)
            pending = nil

            let group = entry.group.flatMap { $0.isEmpty ? nil : $0 }
            let key = entry.name.lowercased() + "|" + (group ?? "")
            if mergeDuplicates, let index = indexByKey[key] {
                if !channels[index].streamURLs.contains(url) {
                    channels[index].streamURLs.append(url)
                }
                continue
            }
            indexByKey[key] = channels.count
            channels.append(Channel(name: entry.name, group: group, logoURL: entry.logoURL, tvgID: entry.tvgID, streamURLs: [url]))
        }

        guard !channels.isEmpty else { throw M3UParserError.noEntries }
        return channels
    }

    // MARK: - Private

    private struct PendingEntry {
        var name: String
        var group: String?
        var logoURL: URL?
        var tvgID: String?
    }

    private static let attributeRegex = try! NSRegularExpression(pattern: #"([A-Za-z0-9_-]+)\s*=\s*"([^"]*)""#)

    /// `#EXTINF:-1 tvg-id="x" tvg-logo="y" group-title="News, World",Channel Name`
    private static func parseExtInf(_ line: String) -> PendingEntry {
        let body = line.drop(while: { $0 != ":" }).dropFirst()

        // The display name follows the first comma that is not inside quotes.
        var inQuotes = false
        var commaIndex: Substring.Index?
        for index in body.indices {
            let char = body[index]
            if char == "\"" { inQuotes.toggle() }
            if char == ",", !inQuotes { commaIndex = index; break }
        }
        let attributePart = commaIndex.map { String(body[..<$0]) } ?? String(body)
        let namePart = commaIndex.map { String(body[body.index(after: $0)...]) } ?? ""

        var attributes: [String: String] = [:]
        let range = NSRange(attributePart.startIndex..., in: attributePart)
        for match in attributeRegex.matches(in: attributePart, range: range) {
            guard let keyRange = Range(match.range(at: 1), in: attributePart),
                  let valueRange = Range(match.range(at: 2), in: attributePart) else { continue }
            attributes[attributePart[keyRange].lowercased()] = String(attributePart[valueRange])
        }

        var name = namePart.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { name = attributes["tvg-name"] ?? "Untitled" }

        return PendingEntry(
            name: name,
            group: attributes["group-title"],
            logoURL: attributes["tvg-logo"].flatMap { $0.isEmpty ? nil : URL(string: $0) },
            tvgID: attributes["tvg-id"].flatMap { $0.isEmpty ? nil : $0 }
        )
    }

    private static func makeURL(_ string: String) -> URL? {
        let url = URL(string: string)
            ?? string.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed).flatMap(URL.init(string:))
        guard let url, url.scheme != nil else { return nil }
        return url
    }
}
