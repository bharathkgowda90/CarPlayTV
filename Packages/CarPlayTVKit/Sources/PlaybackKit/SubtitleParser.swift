import Foundation

public struct SubtitleCue: Hashable, Sendable {
    public let start: Double
    public let end: Double
    public let text: String
}

/// Parses SRT and WebVTT subtitle files for external subtitles shown by our own overlay
/// (which is what lets the user nudge timing while watching).
public enum SubtitleParser {
    public static func parse(_ text: String) -> [SubtitleCue] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
        var cues: [SubtitleCue] = []
        for block in normalized.components(separatedBy: "\n\n") {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let parts = lines[timingIndex].components(separatedBy: "-->")
            guard parts.count == 2,
                  let start = parseTime(parts[0]),
                  let end = parseTime(parts[1].trimmingCharacters(in: .whitespaces).components(separatedBy: " ").first ?? "")
            else { continue }
            let body = lines[(timingIndex + 1)...]
                .map(stripTags)
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { continue }
            cues.append(SubtitleCue(start: start, end: end, text: body))
        }
        return cues.sorted { $0.start < $1.start }
    }

    /// The cue text to show at `time`, or nil.
    public static func text(at time: Double, in cues: [SubtitleCue]) -> String? {
        // Binary search for the last cue starting at or before `time`.
        var low = 0, high = cues.count - 1, found = -1
        while low <= high {
            let mid = (low + high) / 2
            if cues[mid].start <= time { found = mid; low = mid + 1 } else { high = mid - 1 }
        }
        guard found >= 0 else { return nil }
        // Overlapping cues: show all that are active.
        var active: [String] = []
        var index = found
        while index >= 0, found - index < 5 {
            if cues[index].start <= time, time < cues[index].end { active.insert(cues[index].text, at: 0) }
            index -= 1
        }
        return active.isEmpty ? nil : active.joined(separator: "\n")
    }

    /// `00:01:02,500`, `00:01:02.500` or `01:02.500`.
    static func parseTime(_ raw: String) -> Double? {
        let string = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let fields = string.split(separator: ":").map(String.init)
        guard (2...3).contains(fields.count), let seconds = Double(fields.last!) else { return nil }
        let numbers = fields.dropLast().compactMap { Int($0) }
        guard numbers.count == fields.count - 1 else { return nil }
        let hours = numbers.count == 2 ? numbers[0] : 0
        let minutes = numbers.last ?? 0
        return Double(hours * 3600 + minutes * 60) + seconds
    }

    private static func stripTags(_ line: String) -> String {
        line.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\{\\\\[^}]*\\}", with: "", options: .regularExpression)
    }
}
