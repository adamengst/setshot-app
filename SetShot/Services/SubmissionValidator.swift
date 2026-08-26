import Foundation

/// Checks typed text against the rules the submission service enforces, so a
/// problem is explained here rather than coming back as a bare rejection.
///
/// The service refuses links, HTML tags and overlong notes. It has to — the text
/// goes straight into an issue — but it can only answer yes or no, so a submission
/// written with a support-page link, or the word `<Tab>`, used to fail with
/// "Submission failed. Please try again", which is advice that cannot work.
///
/// These rules mirror the service's. If they drift, the service still refuses and
/// the sheet falls back to its generic message, so this can only be too lenient,
/// never too strict.
enum SubmissionValidator {

    static let maxNotesLength = 1000

    // The service triggers on the scheme alone; this carries on to the end of the
    // token so the message can quote the whole thing rather than just "https://".
    private static let link = try! NSRegularExpression(
        pattern: #"(https?://|ftp://|javascript:)\S*"#, options: .caseInsensitive)
    private static let tag = try! NSRegularExpression(
        pattern: #"</?[a-z][a-z0-9]*(\s[^<>]*)?>"#, options: .caseInsensitive)

    /// A sentence explaining what to change, or nil when the notes will be accepted.
    static func problem(withNotes notes: String) -> String? {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let match = firstMatch(of: link, in: trimmed) {
            return "Links can’t be included in a submission — please remove “\(match)” "
                 + "and describe what it points to instead."
        }
        if let match = firstMatch(of: tag, in: trimmed) {
            return "Text in angle brackets can’t be included in a submission, because it "
                 + "may be read as HTML. Please rewrite “\(match)” without them."
        }
        if trimmed.count > maxNotesLength {
            return "Notes are limited to \(maxNotesLength) characters, and this is "
                 + "\(trimmed.count). Please shorten it by \(trimmed.count - maxNotesLength)."
        }
        return nil
    }

    private static func firstMatch(of regex: NSRegularExpression, in text: String) -> String? {
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length))
        else { return nil }
        return ns.substring(with: m.range)
    }
}
