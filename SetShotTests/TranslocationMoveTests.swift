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

    // MARK: - Quarantine

    /// `moveItem` keeps the quarantine flag that Finder's drag would clear, and a
    /// bundle that still carries it is translocated again on the next launch. This
    /// covers the clearing on its own, since the successful move cannot be exercised.
    func testItClearsTheQuarantineFlagFromTheBundleAndItsContents() throws {
        let bundle = tempDirectory.appendingPathComponent("SetShot.app")
        let nested = bundle.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let executable = nested.appendingPathComponent("SetShot")
        try Data("binary".utf8).write(to: executable)

        let flag = "0081;68b4c0d0;Safari;"
        for url in [bundle, executable] {
            try Self.setQuarantine(flag, on: url)
            XCTAssertEqual(try Self.quarantine(of: url), flag, "Test setup did not take")
        }

        Translocation.clearQuarantine(at: bundle)

        XCTAssertNil(try Self.quarantine(of: bundle), "The bundle is still quarantined")
        XCTAssertNil(try Self.quarantine(of: executable), "A nested file is still quarantined")
    }

    func testClearingQuarantineOnSomethingWithoutItIsHarmless() throws {
        let plain = tempDirectory.appendingPathComponent("plain")
        try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)

        Translocation.clearQuarantine(at: plain)

        XCTAssertNil(try Self.quarantine(of: plain))
        XCTAssertTrue(FileManager.default.fileExists(atPath: plain.path),
                      "Clearing the flag removed the item")
    }

    // MARK: - Helpers

    private static func setQuarantine(_ value: String, on url: URL) throws {
        let bytes = Array(value.utf8)
        let result = setxattr(url.path, "com.apple.quarantine", bytes, bytes.count, 0, XATTR_NOFOLLOW)
        if result != 0 { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    }

    /// nil when the attribute is absent, which is what clearing it should produce.
    private static func quarantine(of url: URL) throws -> String? {
        let size = getxattr(url.path, "com.apple.quarantine", nil, 0, 0, XATTR_NOFOLLOW)
        if size < 0 { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        let read = getxattr(url.path, "com.apple.quarantine", &buffer, size, 0, XATTR_NOFOLLOW)
        if read < 0 { return nil }
        return String(decoding: buffer[0..<read], as: UTF8.self)
    }
}
