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
        let url = directory.appendingPathComponent(filename(for: takenAt))
        let compressed = try await gzip(Data(rawOutput.utf8), decompress: false)
        try compressed.write(to: url)
        return StoredSnapshot(url: url, date: takenAt)
    }

    func load(_ snapshot: StoredSnapshot) async throws -> String {
        let data = try Data(contentsOf: snapshot.url)
        if snapshot.url.lastPathComponent.hasSuffix(".gz") {
            let raw = try await gzip(data, decompress: true)
            return String(decoding: raw, as: UTF8.self)
        }
        return String(decoding: data, as: UTF8.self)
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

    private func gzip(_ data: Data, decompress: Bool) async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            let process = Process()
            let inPipe = Pipe()
            let outPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
            process.arguments = decompress ? ["-dc"] : ["-9c"]
            process.standardInput = inPipe
            process.standardOutput = outPipe
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { _ in
                let output = outPipe.fileHandleForReading.readDataToEndOfFile()
                cont.resume(returning: output)
            }
            do {
                try process.run()
                inPipe.fileHandleForWriting.write(data)
                inPipe.fileHandleForWriting.closeFile()
            } catch {
                cont.resume(throwing: error)
            }
        }
    }
}
