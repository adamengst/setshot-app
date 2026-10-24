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

    // Links are refused because the submission queue is read and processed by an
    // agent, not only by a person: a URL in a submission is an invitation to fetch
    // attacker-controlled content and act on what it says. See the matching comment
    // in worker.js, which is where the rule is actually enforced — this copy only
    // explains it early.
    //
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

    // Support messages are checked for length only. The worker accepts links and
    // angle brackets in them, putting the message in a code block instead, because
    // someone asking for help will paste both.
    static let maxSupportMessageLength = 5000
    static let maxNameLength = 100
    static let maxEmailLength = 254

    // The same pattern as EMAIL_PATTERN in worker.js. It is narrow on purpose: the
    // address goes into a mailto: link, so nothing that could end it or start a query
    // is let through.
    private static let email = try! NSRegularExpression(
        pattern: #"^[A-Za-z0-9._+'-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}$"#)

    /// A sentence explaining what to change, or nil when the message will be accepted.
    /// An empty message is not a problem here; the sheet disables Send instead.
    static func problem(withSupportMessage message: String) -> String? {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > maxSupportMessageLength {
            return "Messages are limited to \(maxSupportMessageLength) characters, and this is "
                 + "\(trimmed.count). Please shorten it by \(trimmed.count - maxSupportMessageLength)."
        }
        return nil
    }

    /// A sentence explaining what to change, or nil when the name will be accepted. A
    /// blank name is fine.
    ///
    /// The worker writes the name before the address as "Name <address> writes:", so
    /// angle brackets are refused, along with links, as everywhere else outside the
    /// message itself.
    static func problem(withName name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count > maxNameLength {
            return "Names are limited to \(maxNameLength) characters. Please shorten “\(trimmed.prefix(20))…”."
        }
        if trimmed.contains("<") || trimmed.contains(">") || firstMatch(of: link, in: trimmed) != nil
            || trimmed.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) {
            return "Names can’t include links or angle brackets. Please enter just your name."
        }
        return nil
    }

    /// A sentence explaining what to change, or nil when the address will be accepted.
    /// A blank address is fine; it means no reply is wanted.
    static func problem(withEmail address: String) -> String? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let ns = trimmed as NSString
        if trimmed.utf16.count > maxEmailLength
            || email.firstMatch(in: trimmed, range: NSRange(location: 0, length: ns.length)) == nil {
            return "“\(trimmed)” doesn’t look like an email address SetShot can accept. "
                 + "Please check it, or leave the field empty if you don’t need a reply."
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
