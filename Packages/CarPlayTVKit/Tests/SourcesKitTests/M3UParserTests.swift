import XCTest
@testable import SourcesKit

final class M3UParserTests: XCTestCase {
    func testParsesExtendedEntriesWithAttributes() throws {
        let text = """
        #EXTM3U
        #EXTINF:-1 tvg-id="news.1" tvg-logo="https://example.com/news.png" group-title="News",News One
        https://example.com/news/index.m3u8
        #EXTINF:-1 group-title="Sport",Sport HD
        http://example.com/sport.ts
        """
        let channels = try M3UParser().parse(text)

        XCTAssertEqual(channels.count, 2)
        XCTAssertEqual(channels[0].name, "News One")
        XCTAssertEqual(channels[0].group, "News")
        XCTAssertEqual(channels[0].tvgID, "news.1")
        XCTAssertEqual(channels[0].logoURL, URL(string: "https://example.com/news.png"))
        XCTAssertEqual(channels[0].streamURLs, [URL(string: "https://example.com/news/index.m3u8")!])
        XCTAssertEqual(channels[1].group, "Sport")
    }

    func testCommaInsideQuotedAttributeDoesNotSplitName() throws {
        let text = """
        #EXTINF:-1 group-title="News, World",BBC, World
        https://example.com/a.m3u8
        """
        let channel = try XCTUnwrap(M3UParser().parse(text).first)
        XCTAssertEqual(channel.group, "News, World")
        XCTAssertEqual(channel.name, "BBC, World")
    }

    func testHandlesCRLFBOMAndExtGrp() throws {
        let text = "\u{FEFF}#EXTM3U\r\n#EXTINF:-1,Movie\r\n#EXTGRP:Films\r\n#EXTVLCOPT:http-user-agent=x\r\nhttps://example.com/movie.mp4\r\n"
        let channel = try XCTUnwrap(M3UParser().parse(text).first)
        XCTAssertEqual(channel.name, "Movie")
        XCTAssertEqual(channel.group, "Films")
        XCTAssertEqual(channel.streamURLs.count, 1)
    }

    func testMergesDuplicatesIntoLines() throws {
        let text = """
        #EXTINF:-1 group-title="News",News One
        https://a.example.com/1.m3u8
        #EXTINF:-1 group-title="News",news one
        https://b.example.com/1.m3u8
        #EXTINF:-1 group-title="News",News One
        https://a.example.com/1.m3u8
        """
        let merged = try M3UParser().parse(text)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].streamURLs.count, 2)

        let separate = try M3UParser(mergeDuplicates: false).parse(text)
        XCTAssertEqual(separate.count, 3)
    }

    func testPlainURLListWithoutExtInf() throws {
        let channels = try M3UParser().parse("https://example.com/live/stream.m3u8\nnot a url\n")
        XCTAssertEqual(channels.count, 1)
        XCTAssertEqual(channels[0].name, "stream.m3u8")
    }

    func testFallsBackToTvgNameWhenDisplayNameMissing() throws {
        let text = """
        #EXTINF:-1 tvg-name="Fallback",
        https://example.com/x.m3u8
        """
        XCTAssertEqual(try M3UParser().parse(text).first?.name, "Fallback")
    }

    func testEmptyAndEntrylessPlaylistsThrow() {
        XCTAssertThrowsError(try M3UParser().parse("  \n")) { XCTAssertEqual($0 as? M3UParserError, .empty) }
        XCTAssertThrowsError(try M3UParser().parse("#EXTM3U\n#EXTINF:-1,Nothing\n")) {
            XCTAssertEqual($0 as? M3UParserError, .noEntries)
        }
    }

    func testGroupingKeepsFirstSeenOrder() throws {
        let channels = [
            Channel(name: "A", group: "Sport", streamURLs: [URL(string: "https://e.com/a")!]),
            Channel(name: "B", group: nil, streamURLs: [URL(string: "https://e.com/b")!]),
            Channel(name: "C", group: "Sport", streamURLs: [URL(string: "https://e.com/c")!]),
        ]
        let groups = ChannelGroup.grouping(channels)
        XCTAssertEqual(groups.map(\.name), ["Sport", "Channels"])
        XCTAssertEqual(groups[0].channels.map(\.name), ["A", "C"])
    }
}
