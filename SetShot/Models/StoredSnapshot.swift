import Foundation

struct StoredSnapshot: Identifiable, Sendable {
    var id: String { url.lastPathComponent }
    let url: URL
    let date: Date
    let customLabel: String?
    var isBaseSnapshot: Bool = false
    var baseDisplayName: String? = nil
    var baseMacOSMajor: Int? = nil
    var recognizedCount: Int? = nil
    var unrecognizedCount: Int? = nil
    var isScheduled: Bool = false
    var fromBaseline: Bool = false

    var fileSize: Int64? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attrs?[.size] as? Int64
    }

    var formattedFileSize: String {
        guard let bytes = fileSize else { return "" }
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB]
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }

    /// The Mac's name, with the characters a filename cannot carry removed.
    /// Exports are meant to be compared between machines, so the file has to say
    /// which one it came from.
    static var exportComputerName: String {
        let name = Host.current().localizedName ?? "Mac"
        return name.replacingOccurrences(of: "/", with: "-")
                   .replacingOccurrences(of: ":", with: "-")
    }

    private static let filenameDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")   // never localised separators in a filename
        f.dateFormat = "yyyy-MM-dd HHmm"
        return f
    }()

    /// Today's date, for exports that are not about a particular snapshot.
    static var exportDateStamp: String {
        filenameDateFormatter.string(from: Date()).prefix(10).description
    }

    /// Like `displayName`, but never relative. "Today at 15:12" is useless in a file
    /// still sitting in a folder next week, or opened on another Mac.
    var exportLabel: String {
        if let label = baseDisplayName { return label }
        if let label = customLabel { return label }
        return Self.filenameDateFormatter.string(from: date)
    }

    var displayName: String {
        if let label = baseDisplayName { return label }
        if let label = customLabel { return label }
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return "Today at \(date.formatted(.dateTime.hour().minute()))"
        } else if cal.isDateInYesterday(date) {
            return "Yesterday at \(date.formatted(.dateTime.hour().minute()))"
        } else {
            return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        }
    }
}
