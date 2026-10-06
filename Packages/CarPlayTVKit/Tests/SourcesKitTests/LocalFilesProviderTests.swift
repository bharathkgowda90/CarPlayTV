import XCTest
@testable import SourcesKit

final class LocalFilesProviderTests: XCTestCase {
    func testListsOnlyVideosAndImportAvoidsNameClashes() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let library = root.appendingPathComponent("Videos")
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)

        let picked = root.appendingPathComponent("Trip.mp4")
        try Data("x".utf8).write(to: picked)
        try LocalFilesProvider.importFile(at: picked, into: library)
        let second = try LocalFilesProvider.importFile(at: picked, into: library)
        XCTAssertEqual(second.lastPathComponent, "Trip 2.mp4")
        try Data("x".utf8).write(to: library.appendingPathComponent("notes.txt"))

        let videos = try LocalFilesProvider(directory: library).listVideos()
        XCTAssertEqual(Set(videos.map(\.name)), ["Trip", "Trip 2"])
        XCTAssertTrue(videos.allSatisfy { $0.kind == .video && $0.isPlayable })
    }
}
