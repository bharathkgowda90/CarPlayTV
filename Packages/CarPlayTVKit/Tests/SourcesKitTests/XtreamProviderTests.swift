import XCTest
@testable import SourcesKit

final class XtreamProviderTests: XCTestCase {
    private let provider = XtreamProvider(server: URL(string: "http://tv.example.com:8080")!, username: "user", password: "p@ss")

    func testAPIURLIncludesCredentialsAndAction() throws {
        let url = provider.apiURL(action: "get_live_streams")
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.path, "/player_api.php")
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(query["username"], "user")
        XCTAssertEqual(query["password"], "p@ss")
        XCTAssertEqual(query["action"], "get_live_streams")
    }

    func testLiveStreamsDecodeMixedTypesAndGroupByCategoryOrder() throws {
        let categories = try JSONDecoder().decode([XtreamCategory].self, from: Data("""
        [{"category_id":"2","category_name":"Sport"},{"category_id":1,"category_name":"News"}]
        """.utf8))
        let streams = try JSONDecoder().decode([XtreamLiveStream].self, from: Data("""
        [{"stream_id":10,"name":"News 1","stream_icon":"","epg_channel_id":null,"category_id":"1"},
         {"stream_id":"11","name":"Sport 1","stream_icon":"http://img/s.png","category_id":2},
         {"stream_id":12,"name":"Orphan","category_id":null}]
        """.utf8))

        let groups = provider.makeLiveGroups(categories: categories, streams: streams)
        XCTAssertEqual(groups.map(\.name), ["Live · Sport", "Live · News", "Live · Other"])
        let news = try XCTUnwrap(groups[1].channels.first)
        XCTAssertEqual(news.name, "News 1")
        XCTAssertNil(news.logoURL)
        XCTAssertEqual(news.streamURLs.map(\.lastPathComponent), ["10.m3u8", "10.ts"])
        XCTAssertTrue(news.streamURLs[0].absoluteString.hasPrefix("http://tv.example.com:8080/live/user/"))
        XCTAssertEqual(groups[0].channels.first?.logoURL, URL(string: "http://img/s.png"))
    }

    func testSeriesAreContainersAndEpisodesGroupBySeason() throws {
        let series = try JSONDecoder().decode([XtreamSeries].self, from: Data("""
        [{"series_id":5,"name":"Show","cover":"http://img/c.png","plot":"About","category_id":"9"}]
        """.utf8))
        let show = try XCTUnwrap(provider.makeSeriesGroups(categories: [], series: series).first?.channels.first)
        XCTAssertTrue(show.isContainer)
        XCTAssertFalse(show.isPlayable)
        XCTAssertEqual(show.containerID, "5")

        let info = try JSONDecoder().decode(XtreamSeriesInfo.self, from: Data("""
        {"episodes":{"2":[{"id":"202","episode_num":1,"title":"S2E1","container_extension":"mkv","info":[]}],
                     "1":[{"id":"102","episode_num":"2","title":"S1E2","container_extension":"mp4","info":{"duration_secs":"1500"}},
                          {"id":"101","episode_num":"1","title":"S1E1","container_extension":"mp4","info":{}}]}}
        """.utf8))
        let groups = provider.makeEpisodeGroups(info: info, seriesName: "Show")
        XCTAssertEqual(groups.map(\.name), ["Season 1", "Season 2"])
        XCTAssertEqual(groups[0].channels.map(\.name), ["S1E1", "S1E2"])
        XCTAssertEqual(groups[0].channels[1].durationSeconds, 1500)
        XCTAssertEqual(groups[1].channels[0].streamURLs.first?.lastPathComponent, "202.mkv")
    }

    func testSeriesInfoWithEmptyEpisodeArray() throws {
        let info = try JSONDecoder().decode(XtreamSeriesInfo.self, from: Data(#"{"episodes":[]}"#.utf8))
        XCTAssertTrue(provider.makeEpisodeGroups(info: info, seriesName: "X").isEmpty)
    }
}
