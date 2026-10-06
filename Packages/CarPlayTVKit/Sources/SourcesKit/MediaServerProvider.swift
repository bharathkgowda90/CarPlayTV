import Foundation

/// Client for Jellyfin and Emby, which share most of their REST API.
public actor MediaServerProvider: MediaProvider {
    public enum Flavor: String, Sendable {
        case jellyfin, emby

        /// Emby serves its API under `/emby`; Jellyfin at the root.
        var pathPrefix: String { self == .emby ? "emby" : "" }
    }

    public let flavor: Flavor
    public let server: URL
    public let username: String
    private let password: String
    public let sourceID: UUID?
    private let deviceID: String
    private let session: URLSession

    private var auth: (token: String, userID: String)?

    public init(flavor: Flavor, server: URL, username: String, password: String,
                sourceID: UUID? = nil, deviceID: String, session: URLSession = .shared) {
        self.flavor = flavor
        self.server = server
        self.username = username
        self.password = password
        self.sourceID = sourceID
        self.deviceID = deviceID
        self.session = session
    }

    public func loadGroups() async throws -> [ChannelGroup] {
        let (token, userID) = try await authenticate()

        let views: ItemsResponse = try await get(["Users", userID, "Views"], token: token)
        let videoViews = views.items.filter { view in
            guard let type = view.collectionType?.lowercased() else { return true }
            return ["movies", "tvshows", "homevideos", "mixed", "musicvideos", "boxsets"].contains(type)
        }

        var groups: [ChannelGroup] = []

        let resume: ItemsResponse? = try? await get(["Users", userID, "Items", "Resume"], token: token, query: [
            "MediaTypes": "Video", "Limit": "30", "Fields": "Overview",
        ])
        if let resume, !resume.items.isEmpty {
            groups.append(ChannelGroup(id: "\(sourceKey)/resume", name: "Continue Watching",
                                       channels: resume.items.compactMap { channel(for: $0, group: "Continue Watching", token: token) }))
        }

        let key = sourceKey
        let viewGroups = try await withThrowingTaskGroup(of: (Int, ChannelGroup?).self) { taskGroup in
            for (index, view) in videoViews.enumerated() {
                taskGroup.addTask {
                    let items: ItemsResponse = try await self.get(["Users", userID, "Items"], token: token, query: [
                        "ParentId": view.id,
                        "Recursive": "true",
                        "IncludeItemTypes": "Movie,Series,Video,MusicVideo",
                        "SortBy": "SortName",
                        "Limit": "500",
                        "Fields": "Overview",
                    ])
                    let channels = await items.items.asyncCompactMap { await self.channel(for: $0, group: view.name, token: token) }
                    guard !channels.isEmpty else { return (index, nil) }
                    return (index, ChannelGroup(id: "\(key)/\(view.id)", name: view.name ?? "Library", channels: channels))
                }
            }
            var results: [(Int, ChannelGroup?)] = []
            for try await result in taskGroup { results.append(result) }
            return results.sorted { $0.0 < $1.0 }.compactMap(\.1)
        }
        return groups + viewGroups
    }

    public func children(of item: Channel) async throws -> [ChannelGroup] {
        guard item.kind == .series, let seriesID = item.containerID else { return [] }
        let (token, userID) = try await authenticate()
        let episodes: ItemsResponse = try await get(["Shows", seriesID, "Episodes"], token: token, query: [
            "UserId": userID, "Fields": "Overview",
        ])
        var order: [String] = []
        var buckets: [String: [Channel]] = [:]
        for episode in episodes.items {
            let season = episode.seasonName ?? episode.parentIndexNumber.map { "Season \($0)" } ?? "Episodes"
            guard let channel = channel(for: episode, group: season, token: token) else { continue }
            if buckets[season] == nil { order.append(season) }
            buckets[season, default: []].append(channel)
        }
        return order.map { ChannelGroup(id: "\(sourceKey)/\(seriesID)/\($0)", name: $0, channels: buckets[$0] ?? []) }
    }

    // MARK: - Mapping

    private var sourceKey: String { sourceID?.uuidString ?? server.host ?? flavor.rawValue }

    private func channel(for item: ItemDto, group: String?, token: String) -> Channel? {
        let type = item.type ?? ""
        let image = imageURL(itemID: item.id, tag: item.imageTags?["Primary"], token: token)
        let duration = item.runTimeTicks.map { Double($0) / 10_000_000 }
        let baseID = "\(flavor.rawValue):\(sourceKey):\(item.id)"

        if type == "Series" {
            return Channel(id: baseID, name: item.name ?? "Series", group: group, logoURL: image, streamURLs: [],
                           kind: .series, overview: item.overview, sourceID: sourceID, containerID: item.id)
        }
        guard ["Movie", "Episode", "Video", "MusicVideo"].contains(type) else { return nil }

        var name = item.name ?? "Video"
        if type == "Episode", let number = item.indexNumber {
            name = "\(number). \(name)"
        }
        return Channel(
            id: baseID,
            name: name,
            group: group,
            logoURL: image,
            // Direct play first; the server's HLS transcode is the fallback line for
            // containers/codecs the player can't handle.
            streamURLs: [directStreamURL(itemID: item.id, token: token), hlsStreamURL(itemID: item.id, token: token)],
            kind: type == "Movie" ? .movie : (type == "Episode" ? .episode : .video),
            overview: item.overview,
            durationSeconds: duration,
            sourceID: sourceID
        )
    }

    // MARK: - URLs

    private func endpoint(_ path: [String], query: [String: String] = [:]) -> URL {
        var url = server
        if !flavor.pathPrefix.isEmpty { url.appendPathComponent(flavor.pathPrefix) }
        for component in path { url.appendPathComponent(component) }
        guard !query.isEmpty else { return url }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.url!
    }

    private func directStreamURL(itemID: String, token: String) -> URL {
        endpoint(["Videos", itemID, "stream"], query: ["static": "true", "api_key": token, "DeviceId": deviceID])
    }

    private func hlsStreamURL(itemID: String, token: String) -> URL {
        endpoint(["Videos", itemID, "master.m3u8"], query: [
            "MediaSourceId": itemID,
            "api_key": token,
            "DeviceId": deviceID,
            "PlaySessionId": UUID().uuidString,
            "VideoCodec": "h264,hevc",
            "AudioCodec": "aac,mp3,ac3,eac3",
            "TranscodingMaxAudioChannels": "6",
            "SegmentContainer": "ts",
        ])
    }

    private func imageURL(itemID: String, tag: String?, token: String) -> URL? {
        guard let tag else { return nil }
        return endpoint(["Items", itemID, "Images", "Primary"], query: ["maxHeight": "360", "tag": tag, "api_key": token])
    }

    // MARK: - Networking

    private var authorizationHeader: String {
        #"MediaBrowser Client="CarPlayTV", Device="iPhone", DeviceId="\#(deviceID)", Version="1.0""#
    }

    private func authenticate() async throws -> (token: String, userID: String) {
        if let auth { return auth }
        var request = URLRequest(url: endpoint(["Users", "AuthenticateByName"]))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(authorizationHeader, forHTTPHeaderField: "X-Emby-Authorization")
        request.httpBody = try JSONEncoder().encode(["Username": username, "Pw": password])

        let data: Data
        do {
            data = try await HTTP.data(for: request, session: session)
        } catch MediaProviderError.httpStatus(let code) where code == 400 || code == 500 {
            throw MediaProviderError.authenticationFailed
        }
        guard let response = try? JSONDecoder().decode(AuthResponse.self, from: data) else {
            throw MediaProviderError.authenticationFailed
        }
        let result = (token: response.accessToken, userID: response.user.id)
        auth = result
        return result
    }

    private func get<T: Decodable>(_ path: [String], token: String, query: [String: String] = [:]) async throws -> T {
        var request = URLRequest(url: endpoint(path, query: query))
        request.setValue(authorizationHeader, forHTTPHeaderField: "X-Emby-Authorization")
        request.setValue(token, forHTTPHeaderField: "X-Emby-Token")
        let data = try await HTTP.data(for: request, session: session)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw MediaProviderError.invalidResponse
        }
    }
}

// MARK: - API models

struct AuthResponse: Decodable {
    let accessToken: String
    let user: UserDto

    struct UserDto: Decodable {
        let id: String
        enum CodingKeys: String, CodingKey { case id = "Id" }
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "AccessToken"
        case user = "User"
    }
}

struct ItemsResponse: Decodable {
    let items: [ItemDto]
    enum CodingKeys: String, CodingKey { case items = "Items" }
}

struct ItemDto: Decodable {
    let id: String
    let name: String?
    let type: String?
    let collectionType: String?
    let overview: String?
    let runTimeTicks: Int64?
    let indexNumber: Int?
    let parentIndexNumber: Int?
    let seasonName: String?
    let imageTags: [String: String]?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case type = "Type"
        case collectionType = "CollectionType"
        case overview = "Overview"
        case runTimeTicks = "RunTimeTicks"
        case indexNumber = "IndexNumber"
        case parentIndexNumber = "ParentIndexNumber"
        case seasonName = "SeasonName"
        case imageTags = "ImageTags"
    }
}

extension Sequence {
    func asyncCompactMap<T>(_ transform: (Element) async throws -> T?) async rethrows -> [T] {
        var results: [T] = []
        for element in self {
            if let value = try await transform(element) { results.append(value) }
        }
        return results
    }
}
