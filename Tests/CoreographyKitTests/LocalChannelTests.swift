import Foundation
import XCTest
@testable import CoreographyKit

final class LocalChannelTests: XCTestCase {
    private var directory: URL!
    // Short: socket paths are limited to about 100 bytes.
    private var path: String { directory.appendingPathComponent("s.sock").path }

    override func setUp() {
        directory = URL(fileURLWithPath: "/tmp/coreo-\(UUID().uuidString.prefix(8))")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// A second app instance must not take over the first one's endpoint.
    func testASecondListenerLeavesALiveOneServing() async throws {
        let first = try LocalChannelListener(path: path)
        defer { first.close() }
        XCTAssertThrowsError(try LocalChannelListener(path: path))

        let client = try LocalChannelClient.connect(path: path)
        defer { client.close() }
        let accepted = try await first.accept()
        try accepted.write("still here")
        let line = try await client.readLine()
        XCTAssertEqual(line, "still here")
        accepted.close()
    }

    /// Turning access off and on again: the old listener lets go later than the new one binds.
    func testALeftoverFileIsReplacedAndAnOldListenerKeepsItsHandsOffTheNewOne() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: path, contents: Data("left over by a crash".utf8))
        var old: LocalChannelListener? = try LocalChannelListener(path: path)
        old?.close()
        let new = try LocalChannelListener(path: path)
        defer { new.close() }
        old?.close()
        old = nil
        XCTAssertTrue(FileManager.default.fileExists(atPath: path), "the old listener must not remove the new one's socket")
        XCTAssertNoThrow(try LocalChannelClient.connect(path: path).close())
    }

    func testWritesAfterCloseFailAndReadsEnd() async throws {
        let listener = try LocalChannelListener(path: path)
        defer { listener.close() }
        let client = try LocalChannelClient.connect(path: path)
        let accepted = try await listener.accept()
        client.close()
        XCTAssertThrowsError(try client.write("late"))
        let line = try await accepted.readLine()
        XCTAssertNil(line, "the other side sees the end")
        accepted.close()
    }
}
