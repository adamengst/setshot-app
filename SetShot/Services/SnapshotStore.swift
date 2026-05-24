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
        return StoredSnapshot(url: dest, date: takenAt)
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
                guard let date = parseDate(from: url.lastPathComponent) else { return nil }
                return StoredSnapshot(url: url, date: date)
            }
            .sorted { $0.date > $1.date }
    }

    func delete(_ snapshot: StoredSnapshot) throws {
        try FileManager.default.removeItem(at: snapshot.url)
    }

    // MARK: - Private

    private func filename(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmm"
        return "setshot_\(f.string(from: date)).txt.gz"
    }

    private func parseDate(from name: String) -> Date? {
        var s = name
        if s.hasSuffix(".gz") { s = String(s.dropLast(3)) }
        if s.hasSuffix(".txt") { s = String(s.dropLast(4)) }
        guard s.hasPrefix("setshot_") else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmm"
        return f.date(from: String(s.dropFirst(8)))
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
