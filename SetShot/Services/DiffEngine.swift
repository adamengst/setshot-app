import Foundation

struct DiffEngine {
    private static let diffLineRegex = try! NSRegularExpression(
        pattern: #"^([+-])(.*?)\s*::\s*(.*?)\s*=\s*(.*)$"#
    )
    private static let uuidSuffixRegex = try! NSRegularExpression(
        pattern: #"\.[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$"#,
        options: .caseInsensitive
    )

    func diff(before: Snapshot, after: Snapshot, kb: KnowledgeBase) async throws -> DiffResult {
        guard let bundledScript = Bundle.main.url(forResource: "setshot", withExtension: "sh") else {
            throw SnapshotError.scriptNotFound
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let scriptCopy = tempDir.appendingPathComponent("setshot.sh")
        let beforeFile = tempDir.appendingPathComponent("before.txt")
        let afterFile = tempDir.appendingPathComponent("after.txt")

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try FileManager.default.copyItem(at: bundledScript, to: scriptCopy)
        try before.rawOutput.write(to: beforeFile, atomically: true, encoding: .utf8)
        try after.rawOutput.write(to: afterFile, atomically: true, encoding: .utf8)

        let diffOutput = try await captureProcess(
            executable: "/bin/bash",
            arguments: [scriptCopy.path, "diff", beforeFile.path, afterFile.path]
        )

        return parse(diffOutput: diffOutput, kb: kb)
    }

    // Caps to prevent UI hangs when comparing snapshots across major version
    // boundaries (e.g. a snapshot taken before a domain filter change vs. after).
    private static let maxValueLength = 500
    private static let maxUnrecognized = 500

    func parse(diffOutput: String, kb: KnowledgeBase) -> DiffResult {
        let macOSVersion: String = {
            let v = ProcessInfo.processInfo.operatingSystemVersion
            return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        }()

        struct Pair {
            var domain: String
            var key: String
            var rawDomain: String
            var before: String?
            var after: String?
        }
        var pairs: [Pair] = []
        var index: [String: Int] = [:]

        for line in diffOutput.components(separatedBy: "\n") {
            let ns = line as NSString
            guard let match = Self.diffLineRegex.firstMatch(
                in: line, range: NSRange(location: 0, length: ns.length)
            ) else { continue }

            func capture(_ i: Int) -> String { ns.substring(with: match.range(at: i)) }

            let sign = capture(1)
            let rawDomain = capture(2)
            let key = capture(3)
            let rawValue = capture(4)
            let value = rawValue.count > Self.maxValueLength
                ? String(rawValue.prefix(Self.maxValueLength)) + "…"
                : rawValue
            let normDomain = normalizeDomain(rawDomain)
            let pairKey = "\(normDomain)::\(key)"

            if let idx = index[pairKey] {
                if sign == "+" {
                    pairs[idx].after = value
                } else {
                    pairs[idx].before = value
                }
            } else {
                index[pairKey] = pairs.count
                var p = Pair(domain: normDomain, key: key, rawDomain: rawDomain)
                if sign == "-" { p.before = value } else { p.after = value }
                pairs.append(p)
            }
        }

        var recognized: [(entry: KBEntry, diff: DiffLine)] = []
        var unrecognized: [DiffLine] = []
        var noise: [(entry: KBEntry, diff: DiffLine)] = []

        for p in pairs {
            let before = p.before ?? ""
            let after = p.after ?? ""
            guard semanticValue(before) != semanticValue(after) else { continue }
            let diffLine = DiffLine(
                domain: p.domain,
                key: p.key,
                source: inferSource(rawDomain: p.rawDomain),
                beforeValue: before,
                afterValue: after,
                macOSVersion: macOSVersion,
                rawLine: "\(p.rawDomain) :: \(p.key)"
            )
            if let entry = kb.entry(forDomain: p.domain, key: p.key) {
                if entry.noise {
                    noise.append((entry, diffLine))
                } else {
                    recognized.append((entry, diffLine))
                }
            } else {
                unrecognized.append(diffLine)
            }
        }

        let overflow = max(0, unrecognized.count - Self.maxUnrecognized)
        if overflow > 0 { unrecognized = Array(unrecognized.prefix(Self.maxUnrecognized)) }

        return DiffResult(recognized: recognized, unrecognized: unrecognized, noise: noise, unrecognizedOverflow: overflow)
    }

    private func normalizeDomain(_ raw: String) -> String {
        var domain = raw
        if domain.contains("/") {
            domain = URL(fileURLWithPath: domain).lastPathComponent
        }
        // Strip .plist before UUID: ByHost filenames are "com.apple.foo.UUID.plist",
        // and the UUID regex anchors at $, so it won't match when .plist trails.
        if domain.hasSuffix(".plist") {
            domain = String(domain.dropLast(6))
        }
        let ns = domain as NSString
        let range = NSRange(location: 0, length: ns.length)
        domain = Self.uuidSuffixRegex.stringByReplacingMatches(
            in: domain, range: range, withTemplate: ""
        )
        if domain == ".GlobalPreferences" {
            domain = "NSGlobalDomain"
        }
        return domain
    }

    private func semanticValue(_ value: String) -> String {
        switch value.lowercased() {
        case "true", "yes", "1": return "1"
        case "false", "no", "0": return "0"
        default: return value
        }
    }

    private func inferSource(rawDomain: String) -> String {
        if rawDomain.contains("TCC") { return "tcc" }
        if rawDomain.contains("/") { return "plist" }
        let lower = rawDomain.lowercased()
        if lower.contains("scutil") { return "scutil" }
        if lower.contains("pmset") { return "pmset" }
        if lower.contains("networksetup") { return "networksetup" }
        if lower.contains("systemsetup") { return "systemsetup" }
        return "defaults"
    }

    // Write stdout to a temp file rather than a Pipe to avoid the 64 KB pipe
    // buffer deadlock: large diff output would block the process before it
    // terminates, so the termination handler would never fire.
    private func captureProcess(executable: String, arguments: [String]) async throws -> String {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".txt")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: outputURL) }
        return try await withCheckedThrowingContinuation { continuation in
            do {
                let outHandle = try FileHandle(forWritingTo: outputURL)
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.standardOutput = outHandle
                process.standardError = FileHandle.nullDevice
                process.terminationHandler = { _ in
                    try? outHandle.close()
                    let text = (try? String(contentsOf: outputURL, encoding: .utf8)) ?? ""
                    continuation.resume(returning: text)
                }
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}


