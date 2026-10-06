import XCTest
@testable import MirrorKit

final class MirrorProtocolTests: XCTestCase {
    func testRoundTripAcrossArbitraryChunks() {
        let messages: [MirrorMessage] = [
            .format(sps: Data([0x67, 1, 2, 3]), pps: Data([0x68, 9])),
            .frame(timestamp: 12.345, isKeyframe: true, orientation: 6, data: Data(repeating: 0xAB, count: 3000)),
            .frame(timestamp: 12.378, isKeyframe: false, orientation: 1, data: Data([0, 0, 0, 1, 0x41])),
        ]
        let stream = messages.reduce(Data()) { $0 + $1.encoded() }

        for chunkSize in [1, 7, 512, stream.count] {
            var reader = MirrorStreamReader()
            var received: [MirrorMessage] = []
            var index = 0
            while index < stream.count {
                let end = Swift.min(index + chunkSize, stream.count)
                received += reader.append(stream.subdata(in: index..<end))
                index = end
            }
            XCTAssertEqual(received, messages, "chunk size \(chunkSize)")
        }
    }

    func testCorruptStreamStops() {
        var reader = MirrorStreamReader()
        XCTAssertTrue(reader.append(Data([9, 0, 0, 0, 1, 0])).isEmpty)
        XCTAssertTrue(reader.isCorrupt)
    }
}
