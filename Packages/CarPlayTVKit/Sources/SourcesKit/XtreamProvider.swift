import Foundation

/// Xtream Codes "player_api" client: live TV, movies (VOD) and series.
public struct XtreamProvider: MediaProvider {
    public let server: URL
    public let username: String
    let password: String
    public let sourceID: UUID?
    let session: URLSession

    public init(server: URL, username: String, password: String, sourceID: UUID? = nil, session: URLSession = .shared) {
        self.server = server
        self.username = username
        self.password = password
        self.sourceID = sourceID
        self.session = session
    }

    public func loadGroups() async throws -> [ChannelGroup] {
        async let liveCategories = fetch([XtreamCategory].self, action: "get_live_categories")
        async let liveStreams = fetch([XtreamLiveStream].self, action: "get_live_streams")
        async let vodCategories = try? fetch([XtreamCategory].self, action: "get_vod_categories")
        async let vodStreams = try? fetch([XtreamVODStream].self, action: "get_vod_streams")
        async let seriesCategories = try? fetch([XtreamCategory].self, action: "get_series_categories")
        async let series = try? fetch([XtreamSeries].self, action: "get_series")

        let live = makeLiveGroups(categories: try await liveCategories, streams: try await liveStreams)
        let movies = makeVODGroups(categories: await vodCategories ?? [], streams: await vodStreams ?? [])
        let shows = makeSeriesGroups(categories: await seriesCategories ?? [], series: await series ?? [])
        return live + movies + shows
    }

    public func children(of item: Channel) async throws -> [ChannelGroup] {
        guard item.kind == .series, let seriesID = item.containerID else { return [] }
        let info = try await fetch(XtreamSeriesInfo.self, action: "get_series_info",
                                   extra: [URLQueryItem(name: "series_id", value: seriesID)])
        return makeEpisodeGroups(info: info, seriesName: item.name)
    }

    // MARK: - URLs

    func apiURL(action: String?, extra: [URLQueryItem] = []) -> URL {
        var components = URLComponents(url: server.appendingPathComponent("player_api.php"), resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "username", value: username), URLQueryItem(name: "password", value: password)]
        if let action { items.append(URLQueryItem(name: "action", value: action)) }
        components.queryItems = items + extra
        return components.url!
    }

    func streamURL(kind: String, id: String, ext: String) -> URL {
        server.appendingPathComponent(kind)
            .appendingPathComponent(username)
            .appendingPathComponent(password)
            .appendingPathComponent("\(id).\(ext)")
    }

    // MARK: - Mapping (internal for tests)

    func makeLiveGroups(categories: [XtreamCategory], streams: [XtreamLiveStream]) -> [ChannelGroup] {
        let channels = streams.map { stream in
            Channel(
                id: "xtream:\(sourceKey):live:\(stream.streamID.value)",
                name: stream.name ?? "Channel \(stream.streamID.value)",
                logoURL: Self.url(stream.streamIcon),
                tvgID: stream.epgChannelID.flatMap { $0.isEmpty ? nil : $0 },
                // HLS first (AVPlayer-native), MPEG-TS as a second line.
                streamURLs: [streamURL(kind: "live", id: stream.streamID.value, ext: "m3u8"),
                             streamURL(kind: "live", id: stream.streamID.value, ext: "ts")],
                kind: .live,
                sourceID: sourceID
            )
        }
        return group(channels, by: streams.map { $0.categoryID?.value }, categories: categories, prefix: "Live")
    }

    func makeVODGroups(categories: [XtreamCategory], streams: [XtreamVODStream]) -> [ChannelGroup] {
        let channels = streams.map { stream in
            Channel(
                id: "xtream:\(sourceKey):vod:\(stream.streamID.value)",
                name: stream.name ?? "Movie \(stream.streamID.value)",
                logoURL: Self.url(stream.streamIcon),
                streamURLs: [streamURL(kind: "movie", id: stream.streamID.value, ext: stream.containerExtension ?? "mp4")],
                kind: .movie,
                sourceID: sourceID
            )
        }
        return group(channels, by: streams.map { $0.categoryID?.value }, categories: categories, prefix: "Movies")
    }

    func makeSeriesGroups(categories: [XtreamCategory], series: [XtreamSeries]) -> [ChannelGroup] {
        let channels = series.map { show in
            Channel(
                id: "xtream:\(sourceKey):series:\(show.seriesID.value)",
                name: show.name ?? "Series \(show.seriesID.value)",
                logoURL: Self.url(show.cover),
                streamURLs: [],
                kind: .series,
                overview: show.plot,
                sourceID: sourceID,
                containerID: show.seriesID.value
            )
        }
        return group(channels, by: series.map { $0.categoryID?.value }, categories: categories, prefix: "Series")
    }

    func makeEpisodeGroups(info: XtreamSeriesInfo, seriesName: String) -> [ChannelGroup] {
        let seasons = (info.episodes ?? [:]).keys.sorted { (Int($0) ?? 0) < (Int($1) ?? 0) }
        return seasons.compactMap { season in
            let episodes = (info.episodes?[season] ?? []).sorted {
                (Int($0.episodeNum?.value ?? "") ?? 0) < (Int($1.episodeNum?.value ?? "") ?? 0)
            }
            let channels = episodes.map { episode in
                Channel(
                    id: "xtream:\(sourceKey):episode:\(episode.id.value)",
                    name: episode.title ?? "Episode \(episode.episodeNum?.value ?? "")",
                    group: "Season \(season)",
                    logoURL: Self.url(episode.info?.movieImage),
                    streamURLs: [streamURL(kind: "series", id: episode.id.value, ext: episode.containerExtension ?? "mp4")],
                    kind: .episode,
                    overview: episode.info?.plot,
                    durationSeconds: episode.info?.durationSecs.flatMap { Double($0.value) },
                    sourceID: sourceID
                )
            }
            guard !channels.isEmpty else { return nil }
            return ChannelGroup(id: "\(sourceKey)/\(seriesName)/S\(season)", name: "Season \(season)", channels: channels)
        }
    }

    // MARK: - Private

    private var sourceKey: String { sourceID?.uuidString ?? server.host ?? "xtream" }

    private func group(_ channels: [Channel], by categoryIDs: [String?], categories: [XtreamCategory], prefix: String) -> [ChannelGroup] {
        var buckets: [String: [Channel]] = [:]
        for (channel, categoryID) in zip(channels, categoryIDs) {
            buckets[categoryID ?? "", default: []].append(channel)
        }
        var groups: [ChannelGroup] = []
        var used: Set<String> = []
        for category in categories {
            let id = category.categoryID.value
            guard let items = buckets[id], !items.isEmpty, !used.contains(id) else { continue }
            used.insert(id)
            let name = "\(prefix) · \(category.categoryName ?? "Other")"
            groups.append(ChannelGroup(id: "\(sourceKey)/\(prefix)/\(id)", name: name, channels: items))
        }
        let leftovers = buckets.filter { !used.contains($0.key) }.sorted { $0.key < $1.key }.flatMap(\.value)
        if !leftovers.isEmpty {
            groups.append(ChannelGroup(id: "\(sourceKey)/\(prefix)/other", name: "\(prefix) · Other", channels: leftovers))
        }
        return groups
    }

    private func fetch<T: Decodable>(_ type: T.Type, action: String, extra: [URLQueryItem] = []) async throws -> T {
        let data = try await HTTP.data(for: URLRequest(url: apiURL(action: action, extra: extra)), session: session)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw MediaProviderError.invalidResponse
        }
    }

    private static func url(_ string: String?) -> URL? {
        guard let string, !string.isEmpty else { return nil }
        return URL(string: string)
    }
}

// MARK: - API models

struct XtreamCategory: Decodable {
    let categoryID: FlexibleString
    let categoryName: String?

    enum CodingKeys: String, CodingKey {
        case categoryID = "category_id"
        case categoryName = "category_name"
    }
}

struct XtreamLiveStream: Decodable {
    let streamID: FlexibleString
    let name: String?
    let streamIcon: String?
    let epgChannelID: String?
    let categoryID: FlexibleString?

    enum CodingKeys: String, CodingKey {
        case streamID = "stream_id"
        case name
        case streamIcon = "stream_icon"
        case epgChannelID = "epg_channel_id"
        case categoryID = "category_id"
    }
}

struct XtreamVODStream: Decodable {
    let streamID: FlexibleString
    let name: String?
    let streamIcon: String?
    let categoryID: FlexibleString?
    let containerExtension: String?

    enum CodingKeys: String, CodingKey {
        case streamID = "stream_id"
        case name
        case streamIcon = "stream_icon"
        case categoryID = "category_id"
        case containerExtension = "container_extension"
    }
}

struct XtreamSeries: Decodable {
    let seriesID: FlexibleString
    let name: String?
    let cover: String?
    let plot: String?
    let categoryID: FlexibleString?

    enum CodingKeys: String, CodingKey {
        case seriesID = "series_id"
        case name, cover, plot
        case categoryID = "category_id"
    }
}

struct XtreamSeriesInfo: Decodable {
    let episodes: [String: [XtreamEpisode]]?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Some servers send `[]` instead of `{}` when there are no episodes.
        episodes = try? container.decodeIfPresent([String: [XtreamEpisode]].self, forKey: .episodes)
    }

    enum CodingKeys: String, CodingKey { case episodes }
}

struct XtreamEpisode: Decodable {
    let id: FlexibleString
    let episodeNum: FlexibleString?
    let title: String?
    let containerExtension: String?
    let info: Info?

    struct Info: Decodable {
        let movieImage: String?
        let plot: String?
        let durationSecs: FlexibleString?

        enum CodingKeys: String, CodingKey {
            case movieImage = "movie_image"
            case plot
            case durationSecs = "duration_secs"
        }

        init(from decoder: Decoder) throws {
            // `info` is sometimes an empty array instead of an object.
            guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
                movieImage = nil; plot = nil; durationSecs = nil
                return
            }
            movieImage = try? container.decodeIfPresent(String.self, forKey: .movieImage)
            plot = try? container.decodeIfPresent(String.self, forKey: .plot)
            durationSecs = try? container.decodeIfPresent(FlexibleString.self, forKey: .durationSecs)
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case episodeNum = "episode_num"
        case title
        case containerExtension = "container_extension"
        case info
    }
}
