import XCTest
@testable import SetShot

/// The successful move is deliberately not exercised here: `originalBundleURL`
/// resolves to the test host when nothing is translocated, so a passing test would
/// move the app running the tests. Only the paths that refuse before touching
/// anything are covered; the move itself is verified against a real translocated
/// launch.
final class TranslocationMoveTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("setshot-move-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func testTheOriginalIsThisBundleWhenNothingIsTranslocated() {
        XCTAssertEqual(Translocation.originalBundleURL(), Bundle.main.bundleURL)
    }

    func testItRefusesADirectoryItCannotWriteTo() {
        XCTAssertThrowsError(
            try Translocation.moveToApplications(into: URL(fileURLWithPath: "/System"))
        ) { error in
            guard case Translocation.MoveFailure.directoryNotWritable = error else {
                return XCTFail("Expected directoryNotWritable, got \(error)")
            }
        }
    }

    func testItRefusesRatherThanReplacingUnasked() throws {
        // Stand something in the way named as the app would be.
        let occupied = tempDirectory.appendingPathComponent(Bundle.main.bundleURL.lastPathComponent)
        try FileManager.default.createDirectory(at: occupied, withIntermediateDirectories: true)

        XCTAssertThrowsError(try Translocation.moveToApplications(into: tempDirectory)) { error in
            guard case Translocation.MoveFailure.alreadyThere = error else {
                return XCTFail("Expected alreadyThere, got \(error)")
            }
        }
        // The refusal has to come before anything moves.
        XCTAssertTrue(FileManager.default.fileExists(atPath: Bundle.main.bundleURL.path),
                      "The app was moved despite the refusal")
    }
}
