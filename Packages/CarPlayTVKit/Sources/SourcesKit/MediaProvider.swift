import Foundation

/// Loads browsable content from one source.
public protocol MediaProvider: Sendable {
    /// Top-level rows for the source (playlist groups, categories, libraries).
    func loadGroups() async throws -> [ChannelGroup]
    /// Children of a container item, e.g. a series' episodes grouped by season.
    func children(of item: Channel) async throws -> [ChannelGroup]
}

extension MediaProvider {
    public func children(of item: Channel) async throws -> [ChannelGroup] { [] }
}

public enum MediaProviderError: LocalizedError, Equatable {
    case missingPassword
    case httpStatus(Int)
    case authenticationFailed
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .missingPassword: return "The password for this source is missing. Edit the source and enter it again."
        case .httpStatus(let code): return "The server answered with HTTP \(code)."
        case .authenticationFailed: return "Sign-in failed. Check the username and password."
        case .invalidResponse: return "The server sent a response CarPlayTV couldn't read."
        }
    }
}

/// Builds the provider for a saved source.
public enum MediaProviderFactory {
    public static func provider(
        for source: Source,
        password: String?,
        localDirectory: URL,
        deviceID: String,
        session: URLSession = .shared
    ) throws -> any MediaProvider {
        switch source.kind {
        case .m3u(let url):
            return M3UProvider(url: url, sourceID: source.id, session: session)
        case .xtream(let server, let username):
            guard let password else { throw MediaProviderError.missingPassword }
            return XtreamProvider(server: server, username: username, password: password, sourceID: source.id, session: session)
        case .jellyfin(let server, let username):
            guard let password else { throw MediaProviderError.missingPassword }
            return MediaServerProvider(flavor: .jellyfin, server: server, username: username, password: password,
                                       sourceID: source.id, deviceID: deviceID, session: session)
        case .emby(let server, let username):
            guard let password else { throw MediaProviderError.missingPassword }
            return MediaServerProvider(flavor: .emby, server: server, username: username, password: password,
                                       sourceID: source.id, deviceID: deviceID, session: session)
        case .localFiles:
            return LocalFilesProvider(directory: localDirectory, sourceID: source.id)
        }
    }
}

// MARK: - Shared helpers

enum HTTP {
    static func data(for request: URLRequest, session: URLSession) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            if http.statusCode == 401 || http.statusCode == 403 { throw MediaProviderError.authenticationFailed }
            throw MediaProviderError.httpStatus(http.statusCode)
        }
        return data
    }
}

/// Decodes a JSON value that servers send as a string, a number, or null.
struct FlexibleString: Decodable, Hashable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = String(int)
        } else if let double = try? container.decode(Double.self) {
            value = double.rounded() == double ? String(Int(double)) : String(double)
        } else {
            value = ""
        }
    }
}
