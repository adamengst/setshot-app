import Foundation
import IOKit.ps
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
    /// Whether the privacy permission databases are readable, meaning SetShot can
    /// detect which apps have been granted privacy permissions. Both require Full
    /// Disk Access.
    ///
    /// The system database carries world-readable POSIX permissions, which is
    /// misleading: TCC denies access(2) on it regardless of mode, so checking the
    /// bits says nothing and the read has to be attempted. It also moved to
    /// /Library/Application Support/com.apple.TCC/TCC.db on macOS 15; older
    /// versions keep it at /var/db/TCC/TCC.db. Opening any of these without Full
    /// Disk Access fails silently — no dialog is shown, because Full Disk Access
    /// cannot be requested, only granted by hand in System Settings.
    ///
    /// Used for the Settings pane's permission state. setshot.sh tests the same
    /// paths itself when deciding what to capture.
    static func canReadSystemTCC() -> Bool {
        let paths = [
            "/Library/Application Support/com.apple.TCC/TCC.db",
            "/var/db/TCC/TCC.db",
            NSHomeDirectory() + "/Library/Application Support/com.apple.TCC/TCC.db",
        ]
        for path in paths {
            if let fh = FileHandle(forReadingAtPath: path) {
                fh.closeFile()
                return true
            }
        }
        return false
    }

    /// Whether the media domains can be read.
    ///
    /// The authorization is the whole answer. Reading those domains can only raise a
    /// permission dialog while the status is notDetermined, and this never returns
    /// true in that case, so nothing here can prompt — currentStatus does not ask,
    /// unlike request().
    ///
    /// This used to also require a stored CheckMusicSettings preference, which the
    /// Settings pane wrote to mirror the authorization. That mirror only updated when
    /// the pane was opened, so granting the permission in System Settings left media
    /// capture off until the user happened to visit Settings, with nothing to show
    /// why.
    static func musicEnabled() -> Bool {
        MusicAuthorization.currentStatus == .authorized
    }

    /// Whether this Mac has an internal battery. Evaluated once at launch and
    /// cached; hardware doesn't change while the app is running.
    static let hasBattery: Bool = {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let list = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        return list.contains { src in
            let desc = IOPSGetPowerSourceDescription(info, src).takeUnretainedValue() as? [String: Any]
            return desc?[kIOPSTypeKey as String] as? String == kIOPSInternalBatteryType
        }
    }()

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
        // Recorded in the snapshot header so a comparison can say which build took it.
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
            env["SETSHOT_VERSION"] = build.map { "\(version) (\($0))" } ?? version
        }
        env["SETSHOT_CHECK_MUSIC"] = Self.musicEnabled() ? "1" : "0"

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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment { process.environment = environment }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        return try await CancellableProcess.run(process) { $0.terminationStatus }
    }
}
