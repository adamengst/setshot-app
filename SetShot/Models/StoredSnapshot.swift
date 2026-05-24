import Foundation

struct StoredSnapshot: Identifiable, Sendable {
    var id: String { url.lastPathComponent }
    let url: URL
    let date: Date

    var displayName: String {
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
