import Foundation
import Observation
import SourcesKit

/// Where a viewer stopped in a movie, episode or local video.
public struct WatchEntry: Codable, Hashable, Sendable, Identifiable {
    public var id: String { channel.id }
    public let channel: Channel
    public var position: Double
    public var duration: Double
    public var updatedAt: Date

    public var progress: Double { duration > 0 ? min(1, position / duration) : 0 }
}

/// On-device store for sources, favorites and watch history. Everything is JSON in the
/// app's Application Support folder; passwords go to the Keychain via `passwordStore`.
@MainActor
@Observable
public final class LibraryStore {
    public private(set) var sources: [Source] = []
    public private(set) var favorites: [Channel] = []
    public private(set) var history: [WatchEntry] = []

    /// Positions shorter than this aren't worth resuming.
    public static let minimumResumeSeconds: Double = 30
    /// Past this fraction an item counts as finished.
    public static let finishedFraction: Double = 0.95

    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let passwordStore: PasswordStore

    public init(directory: URL, passwordStore: PasswordStore = .keychain) {
        self.directory = directory
        self.passwordStore = passwordStore
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        sources = load([Source].self, from: "sources.json") ?? []
        favorites = load([Channel].self, from: "favorites.json") ?? []
        history = load([WatchEntry].self, from: "history.json") ?? []
    }

    // MARK: - Sources

    public func addSource(_ source: Source, password: String? = nil) {
        sources.append(source)
        if let password { passwordStore.set(password, source.passwordAccount) }
        save(sources, to: "sources.json")
    }

    public func updateSource(_ source: Source, password: String? = nil) {
        guard let index = sources.firstIndex(where: { $0.id == source.id }) else { return }
        sources[index] = source
        if let password { passwordStore.set(password, source.passwordAccount) }
        save(sources, to: "sources.json")
    }

    public func removeSource(_ source: Source) {
        sources.removeAll { $0.id == source.id }
        passwordStore.delete(source.passwordAccount)
        favorites.removeAll { $0.sourceID == source.id }
        history.removeAll { $0.channel.sourceID == source.id }
        save(sources, to: "sources.json")
        save(favorites, to: "favorites.json")
        save(history, to: "history.json")
    }

    public func password(for source: Source) -> String? {
        passwordStore.get(source.passwordAccount)
    }

    // MARK: - Favorites

    public func isFavorite(_ channel: Channel) -> Bool {
        favorites.contains { $0.id == channel.id }
    }

    public func toggleFavorite(_ channel: Channel) {
        if isFavorite(channel) {
            favorites.removeAll { $0.id == channel.id }
        } else {
            favorites.append(channel)
        }
        save(favorites, to: "favorites.json")
    }

    // MARK: - History / resume

    /// Records progress for on-demand items. Live channels have no position to resume.
    public func recordProgress(for channel: Channel, position: Double, duration: Double, at date: Date = Date()) {
        guard !channel.isLive, duration.isFinite, duration > 0, position.isFinite else { return }
        history.removeAll { $0.channel.id == channel.id }
        history.insert(WatchEntry(channel: channel, position: position, duration: duration, updatedAt: date), at: 0)
        if history.count > 200 { history.removeLast(history.count - 200) }
        save(history, to: "history.json")
    }

    /// Where to resume, or nil to start from the beginning.
    public func resumePosition(for channel: Channel) -> Double? {
        guard let entry = history.first(where: { $0.channel.id == channel.id }) else { return nil }
        guard entry.position >= Self.minimumResumeSeconds, entry.progress < Self.finishedFraction else { return nil }
        return entry.position
    }

    public var continueWatching: [WatchEntry] {
        history.filter { $0.position >= Self.minimumResumeSeconds && $0.progress < Self.finishedFraction }
    }

    public func clearHistory() {
        history = []
        save(history, to: "history.json")
    }

    // MARK: - Files

    private func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func save<T: Encodable>(_ value: T, to name: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: directory.appendingPathComponent(name), options: .atomic)
    }
}

/// Indirection so tests don't touch the real Keychain.
public struct PasswordStore: Sendable {
    public var get: @Sendable (String) -> String?
    public var set: @Sendable (String, String) -> Void
    public var delete: @Sendable (String) -> Void

    public init(get: @escaping @Sendable (String) -> String?,
                set: @escaping @Sendable (String, String) -> Void,
                delete: @escaping @Sendable (String) -> Void) {
        self.get = get
        self.set = set
        self.delete = delete
    }

    public static let keychain = PasswordStore(
        get: { Keychain.string(for: $0) },
        set: { password, account in Keychain.setString(password, for: account) },
        delete: { Keychain.delete(account: $0) }
    )
}
