import Foundation

struct StoredSnapshot: Identifiable, Sendable {
    var id: String { url.lastPathComponent }
    let url: URL
    let date: Date
    let customLabel: String?
    var isBaseSnapshot: Bool = false
    var baseDisplayName: String? = nil
    var baseMacOSMajor: Int? = nil

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
