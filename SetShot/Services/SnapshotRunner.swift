import Foundation
import MusicKit

enum SnapshotError: LocalizedError {
    case scriptNotFound
    case scriptFailed(Int32)
    case outputMissing

    var errorDescription: String? {
        switch self {
        case .scriptNotFound: return "SetShot shell script not found in app bundle."
        case .scriptFailed(let code): return "Snapshot script exited with code \(code)."
        case .outputMissing: return "Snapshot output file was not created."
        }
    }
}

struct SnapshotRunner {
    /// Whether the system TCC database is readable, meaning SetShot can detect
    /// which apps have been granted privacy permissions. On macOS 15+, the db
    /// moved to /Library/Application Support/com.apple.TCC/TCC.db and became
    /// world-readable. On older macOS, /var/db/TCC/TCC.db requires Full Disk
    /// Access.
    static func canReadSystemTCC() -> Bool {
        let paths = [
            "/Library/Application Support/com.apple.TCC/TCC.db",
            "/var/db/TCC/TCC.db",
        ]
        for path in paths {
            if let fh = FileHandle(forReadingAtPath: path) {
                fh.closeFile()
                return true
            }
        }
        return false
    }

    /// Whether SetShot currently holds the `kTCCServiceMediaLibrary` (Media &
    /// Apple Music) grant. Uses MusicAuthorization.currentStatus — the public
    /// API — which returns the current state without triggering a dialog.
    static func musicGranted() -> Bool {
        MusicAuthorization.currentStatus == .authorized
    }

    func run() async throws -> Snapshot {
        guard let bundledScript = Bundle.main.url(forResource: "setshot", withExtension: "sh") else {
            throw SnapshotError.scriptNotFound
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let scriptCopy = tempDir.appendingPathComponent("setshot.sh")
        let outputFile = tempDir.appendingPathComponent("snapshot.txt")

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try FileManager.default.copyItem(at: bundledScript, to: scriptCopy)

        // Pass our own executable path so setshot.sh can call back into SetShot
        // for plist flattening (--flatten-plist) without requiring python3/CLT.
        var env = ProcessInfo.processInfo.environment
        if let bin = Bundle.main.executableURL?.path {
            env["SETSHOT_BIN"] = bin
        }
        env["SETSHOT_CHECK_TCC"] = Self.canReadSystemTCC() ? "1" : "0"
        env["SETSHOT_CHECK_MUSIC"] = Self.musicGranted() ? "1" : "0"

        let exitCode = try await spawnProcess(
            executable: "/bin/bash",
            arguments: [scriptCopy.path, "snapshot", outputFile.path],
            environment: env
        )

        guard exitCode == 0 else { throw SnapshotError.scriptFailed(exitCode) }
        guard FileManager.default.fileExists(atPath: outputFile.path) else {
            throw SnapshotError.outputMissing
        }

        let rawOutput = try String(contentsOf: outputFile, encoding: .utf8)
        return Snapshot(takenAt: .now, rawOutput: rawOutput)
    }

    private func spawnProcess(
        executable: String,
        arguments: [String],
        environment: [String: String]? = nil
    ) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            if let environment { process.environment = environment }
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { p in
                continuation.resume(returning: p.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
