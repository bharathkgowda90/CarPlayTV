import XCTest
@testable import PlaybackKit

final class SubtitleParserTests: XCTestCase {
    func testParsesSRTWithTagsAndCRLF() {
        let srt = "1\r\n00:00:01,000 --> 00:00:03,500\r\n<i>Hello</i>\r\nthere\r\n\r\n2\r\n00:00:05,000 --> 00:00:06,000\r\n{\\an8}Top\r\n"
        let cues = SubtitleParser.parse(srt)
        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0], SubtitleCue(start: 1, end: 3.5, text: "Hello\nthere"))
        XCTAssertEqual(cues[1].text, "Top")
    }

    func testParsesWebVTTWithShortTimesAndSettings() {
        let vtt = """
        WEBVTT

        00:01.000 --> 00:02.000 align:start
        First

        intro
        01:00:00.000 --> 01:00:01.250
        Late
        """
        let cues = SubtitleParser.parse(vtt)
        XCTAssertEqual(cues.map(\.start), [1, 3600])
        XCTAssertEqual(cues[1].end, 3601.25)
    }

    func testTextAtTime() {
        let cues = [
            SubtitleCue(start: 1, end: 3, text: "A"),
            SubtitleCue(start: 2, end: 4, text: "B"),
            SubtitleCue(start: 10, end: 11, text: "C"),
        ]
        XCTAssertNil(SubtitleParser.text(at: 0.5, in: cues))
        XCTAssertEqual(SubtitleParser.text(at: 1.5, in: cues), "A")
        XCTAssertEqual(SubtitleParser.text(at: 2.5, in: cues), "A\nB")
        XCTAssertNil(SubtitleParser.text(at: 5, in: cues))
        XCTAssertEqual(SubtitleParser.text(at: 10, in: cues), "C")
    }
}
