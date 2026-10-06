import XCTest
@testable import LibraryKit
import SourcesKit

@MainActor
final class LibraryStoreTests: XCTestCase {
    private var directory: URL!
    private final class Box: @unchecked Sendable { var values: [String: String] = [:] }
    private let box = Box()

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeStore() -> LibraryStore {
        let box = self.box
        return LibraryStore(directory: directory, passwordStore: PasswordStore(
            get: { box.values[$0] },
            set: { box.values[$1] = $0 },
            delete: { box.values[$0] = nil }
        ))
    }

    private func movie(_ name: String, source: UUID? = nil) -> Channel {
        Channel(name: name, streamURLs: [URL(string: "https://e.com/\(name).mp4")!], kind: .movie, sourceID: source)
    }

    func testSourcesPersistAndPasswordsGoToPasswordStore() {
        let source = Source(name: "Home", kind: .xtream(server: URL(string: "http://tv.example.com")!, username: "me"))
        makeStore().addSource(source, password: "secret")

        let reloaded = makeStore()
        XCTAssertEqual(reloaded.sources, [source])
        XCTAssertEqual(reloaded.password(for: source), "secret")
        let raw = try? String(contentsOf: directory.appendingPathComponent("sources.json"), encoding: .utf8)
        XCTAssertFalse(raw?.contains("secret") ?? true)
    }

    func testRemovingSourceRemovesItsFavoritesHistoryAndPassword() {
        let store = makeStore()
        let source = Source(name: "Jelly", kind: .jellyfin(server: URL(string: "http://nas:8096")!, username: "me"))
        store.addSource(source, password: "pw")
        let item = movie("A", source: source.id)
        store.toggleFavorite(item)
        store.recordProgress(for: item, position: 100, duration: 1000)

        store.removeSource(source)
        XCTAssertTrue(store.favorites.isEmpty)
        XCTAssertTrue(store.history.isEmpty)
        XCTAssertNil(store.password(for: source))
    }

    func testFavoritesToggleAndPersist() {
        let store = makeStore()
        let item = movie("A")
        store.toggleFavorite(item)
        XCTAssertTrue(makeStore().isFavorite(item))
        store.toggleFavorite(item)
        XCTAssertFalse(makeStore().isFavorite(item))
    }

    func testResumeRules() {
        let store = makeStore()
        let short = movie("Short"), middle = movie("Middle"), done = movie("Done")
        store.recordProgress(for: short, position: 10, duration: 1000)
        store.recordProgress(for: middle, position: 500, duration: 1000)
        store.recordProgress(for: done, position: 990, duration: 1000)

        XCTAssertNil(store.resumePosition(for: short))
        XCTAssertEqual(store.resumePosition(for: middle), 500)
        XCTAssertNil(store.resumePosition(for: done))
        XCTAssertEqual(store.continueWatching.map(\.channel.name), ["Middle"])
    }

    func testLiveChannelsAreNotRecorded() {
        let store = makeStore()
        let live = Channel(name: "News", streamURLs: [URL(string: "https://e.com/live.m3u8")!])
        store.recordProgress(for: live, position: 100, duration: 1000)
        XCTAssertTrue(store.history.isEmpty)
    }

    func testMostRecentFirstAndNoDuplicates() {
        let store = makeStore()
        let a = movie("A"), b = movie("B")
        store.recordProgress(for: a, position: 100, duration: 1000)
        store.recordProgress(for: b, position: 100, duration: 1000)
        store.recordProgress(for: a, position: 200, duration: 1000)
        XCTAssertEqual(store.history.map(\.channel.name), ["A", "B"])
        XCTAssertEqual(store.resumePosition(for: a), 200)
    }
}
