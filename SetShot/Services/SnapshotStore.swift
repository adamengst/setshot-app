import Foundation

actor SnapshotStore {
    static let shared = SnapshotStore()

    nonisolated let directory: URL

    private init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        directory = appSupport.appendingPathComponent("SetShot/snapshots")
    }

    func save(_ rawOutput: String, takenAt: Date = .now) async throws -> StoredSnapshot {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let dest = directory.appendingPathComponent(filename(for: takenAt))
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try Data(rawOutput.utf8).write(to: tmp)
        try await gzipFile(input: tmp, output: dest)
        return StoredSnapshot(url: dest, date: takenAt, customLabel: nil)
    }

    func load(_ snapshot: StoredSnapshot) async throws -> String {
        if snapshot.url.lastPathComponent.hasSuffix(".gz") {
            return try await gunzipFile(snapshot.url)
        }
        return try String(contentsOf: snapshot.url, encoding: .utf8)
    }

    func list() throws -> [StoredSnapshot] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter {
                let n = $0.lastPathComponent
                return n.hasPrefix("setshot_") && (n.hasSuffix(".txt") || n.hasSuffix(".txt.gz"))
            }
            .compactMap { url -> StoredSnapshot? in
                guard let (date, label) = parseDateAndLabel(from: url.lastPathComponent) else { return nil }
                let meta = loadMeta(for: url)
                return StoredSnapshot(url: url, date: date, customLabel: label,
                                      recognizedCount: meta?.recognized,
                                      unrecognizedCount: meta?.unrecognized,
                                      isScheduled: meta?.scheduled ?? false,
                                      fromBaseline: meta?.fromBaseline ?? false)
            }
            .sorted { $0.date > $1.date }
    }

    nonisolated func listBaseSnapshots() -> [StoredSnapshot] {
        let baseDir = Bundle.main.resourceURL?.appendingPathComponent("BaseSnapshots")
        guard let baseDir,
              let items = try? FileManager.default.contentsOfDirectory(
                at: baseDir, includingPropertiesForKeys: nil)
        else { return [] }
        return items
            .filter { $0.lastPathComponent.hasPrefix("base_") && $0.lastPathComponent.hasSuffix(".txt.gz") }
            .compactMap { url -> StoredSnapshot? in
                guard let label = baseLabel(for: url.lastPathComponent) else { return nil }
                let major = baseMajorVersion(for: url.lastPathComponent)
                return StoredSnapshot(url: url, date: .distantPast, customLabel: nil,
                                     isBaseSnapshot: true, baseDisplayName: label,
                                     baseMacOSMajor: major)
            }
            .sorted { ($0.baseDisplayName ?? "") < ($1.baseDisplayName ?? "") }
    }

    func saveMeta(for snapshot: StoredSnapshot, recognized: Int, unrecognized: Int, scheduled: Bool, fromBaseline: Bool = false) throws {
        let meta = SnapshotMeta(recognized: recognized, unrecognized: unrecognized, scheduled: scheduled, fromBaseline: fromBaseline)
        let data = try JSONEncoder().encode(meta)
        try data.write(to: metaURL(for: snapshot.url))
    }

    func delete(_ snapshot: StoredSnapshot) throws {
        try FileManager.default.removeItem(at: snapshot.url)
        try? FileManager.default.removeItem(at: metaURL(for: snapshot.url))
    }

    func rename(_ snapshot: StoredSnapshot, to label: String) throws -> StoredSnapshot {
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmm"
        let dateStr = f.string(from: snapshot.date)
        let newName: String
        let newLabel: String?
        if trimmed.isEmpty {
            newName = "setshot_\(dateStr).txt.gz"
            newLabel = nil
        } else {
            let safe = trimmed.replacingOccurrences(of: "/", with: "-")
            newName = "setshot_\(dateStr)_\(safe).txt.gz"
            newLabel = trimmed
        }
        let newURL = directory.appendingPathComponent(newName)
        if newURL.lastPathComponent != snapshot.url.lastPathComponent {
            let oldMeta = metaURL(for: snapshot.url)
            try FileManager.default.moveItem(at: snapshot.url, to: newURL)
            if FileManager.default.fileExists(atPath: oldMeta.path) {
                try? FileManager.default.moveItem(at: oldMeta, to: metaURL(for: newURL))
            }
        }
        return StoredSnapshot(url: newURL, date: snapshot.date, customLabel: newLabel,
                              recognizedCount: snapshot.recognizedCount,
                              unrecognizedCount: snapshot.unrecognizedCount,
                              isScheduled: snapshot.isScheduled,
                              fromBaseline: snapshot.fromBaseline)
    }

    // MARK: - Private

    private struct SnapshotMeta: Codable {
        var recognized: Int
        var unrecognized: Int
        var scheduled: Bool
        var fromBaseline: Bool = false
    }

    private nonisolated func metaURL(for snapshotURL: URL) -> URL {
        var name = snapshotURL.lastPathComponent
        if name.hasSuffix(".txt.gz") { name = String(name.dropLast(7)) }
        else if name.hasSuffix(".txt") { name = String(name.dropLast(4)) }
        return snapshotURL.deletingLastPathComponent().appendingPathComponent(name + ".meta.json")
    }

    private func loadMeta(for url: URL) -> SnapshotMeta? {
        guard let data = try? Data(contentsOf: metaURL(for: url)) else { return nil }
        return try? JSONDecoder().decode(SnapshotMeta.self, from: data)
    }

    // Derives "macOS Sequoia 15.7.7 baseline defaults" from "base_Sequoia_15.7.7.txt.gz"
    private nonisolated func baseLabel(for filename: String) -> String? {
        var name = filename
        guard name.hasPrefix("base_") else { return nil }
        name = String(name.dropFirst(5))
        if name.hasSuffix(".txt.gz") { name = String(name.dropLast(7)) }
        else if name.hasSuffix(".txt") { name = String(name.dropLast(4)) }
        let parts = name.split(separator: "_", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        return "macOS \(parts[0]) \(parts[1]) baseline defaults"
    }

    private nonisolated func baseMajorVersion(for filename: String) -> Int? {
        var name = filename
        guard name.hasPrefix("base_") else { return nil }
        name = String(name.dropFirst(5))
        if name.hasSuffix(".txt.gz") { name = String(name.dropLast(7)) }
        else if name.hasSuffix(".txt") { name = String(name.dropLast(4)) }
        let parts = name.split(separator: "_", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        return Int(String(parts[1]).split(separator: ".").first ?? "")
    }

    private func filename(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmmss"
        return "setshot_\(f.string(from: date)).txt.gz"
    }

    private func parseDateAndLabel(from name: String) -> (date: Date, label: String?)? {
        var s = name
        if s.hasSuffix(".gz") { s = String(s.dropLast(3)) }
        if s.hasSuffix(".txt") { s = String(s.dropLast(4)) }
        guard s.hasPrefix("setshot_") else { return nil }
        let rest = String(s.dropFirst(8))
        guard rest.count >= 15 else { return nil }
        // Position 15 is a digit only in the seconds format (yyyy-MM-dd_HHmmss = 17 chars);
        // legacy files use minute format (yyyy-MM-dd_HHmm = 15 chars).
        let idx15 = rest.index(rest.startIndex, offsetBy: 15)
        let useSeconds = rest.count > 15 && rest[idx15].isNumber
        let dateLen = useSeconds ? 17 : 15
        guard rest.count >= dateLen else { return nil }
        let dateStr = String(rest.prefix(dateLen))
        let f = DateFormatter()
        f.dateFormat = useSeconds ? "yyyy-MM-dd_HHmmss" : "yyyy-MM-dd_HHmm"
        guard let date = f.date(from: dateStr) else { return nil }
        let suffix = String(rest.dropFirst(dateLen))
        let label = suffix.hasPrefix("_") ? String(suffix.dropFirst()) : nil
        return (date, label.flatMap { $0.isEmpty ? nil : $0 })
    }

    // Use file-based I/O for gzip to avoid Pipe buffer deadlock on large snapshots.
    // Pipe buffers are only 64 KB; a snapshot can be several MB.

    private func gzipFile(input: URL, output: URL) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            do {
                FileManager.default.createFile(atPath: output.path, contents: nil)
                let outHandle = try FileHandle(forWritingTo: output)
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
                process.arguments = ["-9c", input.path]
                process.standardOutput = outHandle
                process.standardError = FileHandle.nullDevice
                process.terminationHandler = { _ in
                    try? outHandle.close()
                    cont.resume()
                }
                try process.run()
            } catch {
                cont.resume(throwing: error)
            }
        }
    }

    private func gunzipFile(_ url: URL) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            do {
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                FileManager.default.createFile(atPath: tmp.path, contents: nil)
                let outHandle = try FileHandle(forWritingTo: tmp)
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
                process.arguments = ["-dc", url.path]
                process.standardOutput = outHandle
                process.standardError = FileHandle.nullDevice
                process.terminationHandler = { _ in
                    try? outHandle.close()
                    let text = (try? String(contentsOf: tmp, encoding: .utf8)) ?? ""
                    try? FileManager.default.removeItem(at: tmp)
                    cont.resume(returning: text)
                }
                try process.run()
            } catch {
                cont.resume(throwing: error)
            }
        }
    }
}
