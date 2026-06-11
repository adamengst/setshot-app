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
