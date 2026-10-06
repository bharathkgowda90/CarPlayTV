import Foundation

public enum PlaylistLoaderError: LocalizedError, Equatable {
    case httpStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .httpStatus(let code): return "The playlist server answered with HTTP \(code)."
        }
    }
}

/// Loads an M3U playlist from a web address or a file picked in the Files app.
public enum PlaylistLoader {
    public static func load(from url: URL, session: URLSession = .shared, parser: M3UParser = M3UParser()) async throws -> [Channel] {
        let data: Data
        if url.isFileURL {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            data = try Data(contentsOf: url)
        } else {
            let (body, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw PlaylistLoaderError.httpStatus(http.statusCode)
            }
            data = body
        }
        return try parser.parse(String(decoding: data, as: UTF8.self))
    }
}
