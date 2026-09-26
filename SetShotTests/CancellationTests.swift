import XCTest
@testable import SetShot

/// A cancelled capture has to stop the `bash` child, not just mark the Task
/// cancelled. Wrapping Process in a bare continuation does the latter: the await
/// never returns and the spinner turns until the script finishes on its own.
final class CancellationTests: XCTestCase {

    /// Captures this process started, not every script on the machine.
    ///
    /// Two filters, and both are needed. Counting every setshot.sh made this fail
    /// whenever another suite happened to be running one at the same moment, because
    /// xcodebuild runs test classes in parallel -- hence the parent pid.
    ///
    /// But every test class shares one xctest process, so the pid matches for scripts
    /// this test knows nothing about. What kept turning up was a `setshot.sh diff`
    /// from whichever comparison test was running alongside, which is not a capture
    /// and cannot have outlived a cancellation that never touched it. Matching the
    /// subcommand is what separates them.
    private func runningSetshotScripts() -> Int { runningSetshotScriptLines().count }

    /// The matching `ps` lines, so a failure can say what outlived the cancellation
    /// rather than only that the count was wrong.
    private func runningSetshotScriptLines() -> [String] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-Ao", "ppid=,command="]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        try? p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let text = String(data: data, encoding: .utf8) ?? ""
        let me = ProcessInfo.processInfo.processIdentifier
        return text.split(separator: "\n").filter { line in
            guard line.contains("setshot.sh snapshot") else { return false }
            let ppid = Int32(line.drop { $0 == " " }.prefix { $0.isNumber }) ?? -1
            return ppid == me
        }.map(String.init)
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
        let leftover = runningSetshotScriptLines()
        XCTAssertLessThanOrEqual(leftover.count, before, """
            A cancelled capture left a setshot.sh child running.

            \(leftover.joined(separator: "\n"))
            """)
    }

    func testAnUncancelledCaptureStillCompletes() async throws {
        let snapshot = try await SnapshotRunner().run()
        XCTAssertFalse(snapshot.rawOutput.isEmpty)
        XCTAssertTrue(snapshot.rawOutput.contains("macOS Settings Snapshot"))
    }
}
