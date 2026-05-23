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

    private func parse(diffOutput: String, kb: KnowledgeBase) -> DiffResult {
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
            let value = capture(4)
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

        var recognised: [(entry: KBEntry, diff: DiffLine)] = []
        var unrecognised: [DiffLine] = []
        var noise: [(entry: KBEntry, diff: DiffLine)] = []

        for p in pairs {
            let diffLine = DiffLine(
                domain: p.domain,
                key: p.key,
                source: inferSource(rawDomain: p.rawDomain),
                beforeValue: p.before ?? "",
                afterValue: p.after ?? "",
                macOSVersion: macOSVersion,
                rawLine: "\(p.rawDomain) :: \(p.key)"
            )
            if let entry = kb.entry(forDomain: p.domain, key: p.key) {
                if entry.noise {
                    noise.append((entry, diffLine))
                } else {
                    recognised.append((entry, diffLine))
                }
            } else {
                unrecognised.append(diffLine)
            }
        }

        return DiffResult(recognised: recognised, unrecognised: unrecognised, noise: noise)
    }

    private func normalizeDomain(_ raw: String) -> String {
        var domain = raw
        if domain.contains("/") {
            domain = URL(fileURLWithPath: domain).lastPathComponent
        }
        let ns = domain as NSString
        let range = NSRange(location: 0, length: ns.length)
        domain = Self.uuidSuffixRegex.stringByReplacingMatches(
            in: domain, range: range, withTemplate: ""
        )
        if domain.hasSuffix(".plist") {
            domain = String(domain.dropLast(6))
        }
        // .GlobalPreferences is the direct-plist path to NSGlobalDomain
        if domain == ".GlobalPreferences" {
            domain = "NSGlobalDomain"
        }
        return domain
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

    private func captureProcess(executable: String, arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
