import XCTest
@testable import SetShot

final class SubmissionServiceTests: XCTestCase {

    // Every installed copy posts to these, so a change to them strands that copy.
    func testEndpointsAreOnSetShotHost() {
        XCTAssertEqual(SubmissionService.endpoint("/submit").absoluteString, "https://setshot.tidbits.com/submit")
        XCTAssertEqual(SubmissionService.endpoint("/kb-feedback").absoluteString, "https://setshot.tidbits.com/kb-feedback")
        XCTAssertEqual(SubmissionService.endpoint("/support").absoluteString, "https://setshot.tidbits.com/support")
    }

    func testChunkingExactSize() {
        let chunks = SubmissionService.chunked(Array(0..<150), size: 150)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].count, 150)
    }

    func testChunkingOneOver() {
        let chunks = SubmissionService.chunked(Array(0..<151), size: 150)
        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0].count, 150)
        XCTAssertEqual(chunks[1].count, 1)
    }

    func testChunkingMultipleFullChunks() {
        let chunks = SubmissionService.chunked(Array(0..<300), size: 150)
        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0].count, 150)
        XCTAssertEqual(chunks[1].count, 150)
    }

    func testChunkingEmpty() {
        let chunks = SubmissionService.chunked([Int](), size: 150)
        XCTAssertEqual(chunks.count, 0)
    }

    func testChunkingSmallBatch() {
        let chunks = SubmissionService.chunked(Array(0..<5), size: 150)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].count, 5)
    }
}
