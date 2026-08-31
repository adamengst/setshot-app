import XCTest
@testable import SetShot

/// A cancelled capture has to stop the `bash` child, not just mark the Task
/// cancelled. Wrapping Process in a bare continuation does the latter: the await
/// never returns and the spinner turns until the script finishes on its own.
final class CancellationTests: XCTestCase {

    private func runningSetshotScripts() -> Int {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-Ao", "command"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        try? p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let text = String(data: data, encoding: .utf8) ?? ""
        return text.split(separator: "\n").filter { $0.contains("setshot.sh") }.count
    }

    func testCancellingACaptureStopsItPromptly() async throws {
        let before = runningSetshotScripts()
        let started = Date()

        let task = Task { try await SnapshotRunner().run() }
        // Long enough that the script is genuinely under way.
        try await Task.sleep(nanoseconds: 300_000_000)
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected the cancelled capture to throw")
        } catch is CancellationError {
            // Expected.
        } catch {
            // A terminated child can surface as a non-zero exit before the
            // cancellation is observed; either way it must not have completed.
        }

        let elapsed = Date().timeIntervalSince(started)
        XCTAssertLessThan(elapsed, 3.0,
                          "Cancelling should return promptly, not wait out the capture")

        // Give the child a moment to be reaped, then confirm nothing was orphaned.
        try await Task.sleep(nanoseconds: 1_500_000_000)
        XCTAssertLessThanOrEqual(runningSetshotScripts(), before,
                                 "A cancelled capture left a setshot.sh child running")
    }

    func testAnUncancelledCaptureStillCompletes() async throws {
        let snapshot = try await SnapshotRunner().run()
        XCTAssertFalse(snapshot.rawOutput.isEmpty)
        XCTAssertTrue(snapshot.rawOutput.contains("macOS Settings Snapshot"))
    }
}
