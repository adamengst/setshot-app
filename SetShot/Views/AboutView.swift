import SwiftUI
import AppKit

// MARK: - Environment

private struct AboutSearchQueryKey: EnvironmentKey {
    static let defaultValue = ""
}
private struct AboutActiveNodeIdKey: EnvironmentKey {
    static let defaultValue = ""
}
private struct AboutActiveOccurrenceKey: EnvironmentKey {
    static let defaultValue = -1
}
extension EnvironmentValues {
    fileprivate var aboutSearchQuery: String {
        get { self[AboutSearchQueryKey.self] }
        set { self[AboutSearchQueryKey.self] = newValue }
    }
    fileprivate var aboutActiveNodeId: String {
        get { self[AboutActiveNodeIdKey.self] }
        set { self[AboutActiveNodeIdKey.self] = newValue }
    }
    fileprivate var aboutActiveOccurrence: Int {
        get { self[AboutActiveOccurrenceKey.self] }
        set { self[AboutActiveOccurrenceKey.self] = newValue }
    }
}

// MARK: - Highlight helpers

private func highlighted(_ text: String, query: String, activeOccurrence: Int = -1) -> AttributedString {
    var attr: AttributedString
    do {
        attr = try AttributedString(markdown: text, options: .init(interpretedSyntax: .full))
    } catch {
        attr = AttributedString(text)
    }
    guard !query.isEmpty else { return attr }
    let plain = String(attr.characters)
    var pos = plain.startIndex
    let chars = attr.characters
    var occIdx = 0
    while let range = plain.range(of: query, options: .caseInsensitive, range: pos..<plain.endIndex) {
        let startOff = plain.distance(from: plain.startIndex, to: range.lowerBound)
        let endOff = plain.distance(from: plain.startIndex, to: range.upperBound)
        let attrStart = chars.index(chars.startIndex, offsetBy: startOff)
        let attrEnd = chars.index(chars.startIndex, offsetBy: endOff)
        var container = AttributeContainer()
        container.swiftUI.backgroundColor = occIdx == activeOccurrence
            ? Color.orange.opacity(0.65)
            : Color.yellow.opacity(0.5)
        attr[attrStart..<attrEnd].mergeAttributes(container)
        pos = range.upperBound
        occIdx += 1
    }
    return attr
}

private func plainTextOccurrenceCount(_ text: String, query: String) -> Int {
    guard !query.isEmpty else { return 0 }
    let attr = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .full))) ?? AttributedString(text)
    let plain = String(attr.characters).lowercased()
    let q = query.lowercased()
    var count = 0
    var pos = plain.startIndex
    while let r = plain.range(of: q, range: pos..<plain.endIndex) {
        count += 1
        pos = r.upperBound
    }
    return count
}

// MARK: - Selectable help content (single NSTextView)

/// One element of help content, used both to build the single selectable
/// NSAttributedString (non-search path) and as documentation of the structure.
private enum HelpContent {
    case title(String)
    case intro(String)
    case section(String)
    case paragraph(String)
    case bullet(String)
    case callout(label: String, content: String)
    case screenshot(String)
}

/// The entire help document, in order. The non-search path renders this as a
/// single NSTextView so text can be selected across paragraphs in one drag.
private let aboutHelpContent: [HelpContent] = [
    .title("About SetShot"),
    .intro("Have you ever thought a macOS update changed some setting silently? Or have you spelunked through System Settings and wondered later what you clicked? With SetShot, you can find out what settings have changed over time, making it easy to see what you've done and revert inadvertent changes."),
    .intro("SetShot lets you capture a complete snapshot of your Mac's settings at any point in time so you can compare any two snapshots and see exactly what changed, in plain English. Each recognized change comes with a description, its location in System Settings, and \u{2014} where possible \u{2014} a button that opens the exact pane directly."),

    .section("SetShot Views"),
    .paragraph("SetShot has four views, accessed by clicking the buttons at the top of the window:"),
    .screenshot("ScreenshotNavigation"),
    .bullet("**Snapshots:** Shows all the snapshots you've taken in Before and After columns."),
    .bullet("**Journal:** A chronological log of all recognized changes across your comparisons."),
    .bullet("**Settings:** Reverse sort order and set up automatic daily snapshots."),
    .bullet("**About:** You're reading it now."),

    .section("Taking Snapshots"),
    .paragraph("SetShot's core function is to take and compare snapshots. To that end, it scans nearly 500 settings files across more than a dozen system data sources. It currently recognizes over 400 settings and knows to ignore over 50 additional changes that are just macOS noise."),
    .paragraph("To take a snapshot of the current state of your Mac's settings, click **Take Snapshot** at the bottom of the Snapshots view. SetShot saves the result to the snapshot library with the date and time. Snapshots are stored in `~/Library/Application Support/SetShot/snapshots` as gzipped files that occupy little space. Capturing typically takes less than a minute."),
    .screenshot("ScreenshotSnapshotsContext"),
    .paragraph("Each snapshot line shows the number of recognized changes from the previous snapshot and the size of the snapshot file."),
    .paragraph("To rename a snapshot, Control-click it and choose **Rename**, then type a new name. Renaming can be useful for labelling snapshots with context \u{2014} for example, \u{2018}Before macOS 26.6\u{2019} or \u{2018}After Accessibility testing.\u{2019}"),
    .paragraph("To remove an unnecessary snapshot, Control-click it and choose **Delete**."),

    .section("Comparing Snapshots"),
    .paragraph("Once you've taken at least two snapshots, you can use SetShot to compare them."),
    .paragraph("The Snapshots view shows two columns. Click a snapshot in the left column to set it as the **Before** snapshot, and click a snapshot in the right column to set it as the **After** snapshot."),
    .screenshot("ScreenshotSnapshotsReady"),
    .paragraph("Once you have selected both snapshots, click **Compare** to run the comparison. The results open in a new window titled with the names of the two snapshots, leaving the snapshot library available so you can start additional comparisons. You can have multiple comparison windows open at once to look at them side by side."),
    .paragraph("SetShot identifies every setting that differs between the two snapshots and looks up each one in its knowledge base to determine whether it's a recognized change or an unrecognized change. Changes to the knowledge base are read at every launch."),

    .section("Understanding Results"),
    .paragraph("Results are divided into two sections:"),
    .callout(label: "Recognized Changes",
             content: "Settings already in SetShot\u{2019}s knowledge base. Each entry shows a plain-English description, the path to find it in System Settings, and \u{2014} where possible \u{2014} an **Open in Settings** button that takes you directly to the relevant pane. The old value appears in orange and the new value in blue. A **Submit Feedback** button lets you flag issues with the description, path, icon, or value formatting to help improve SetShot for everyone."),
    .callout(label: "Unrecognized Changes",
             content: "Changes that are either noise or legitimate settings changes that aren't yet in the knowledge base. The raw technical name of the setting is shown along with its old and new values. You can submit these to help improve SetShot for everyone."),
    .paragraph("Values are displayed in a readable form where possible: toggles show On or Off, volume settings show a percentage, file paths show just the filename, and settings with a fixed list of options (like Hot Corner actions) show the option name rather than a raw number."),
    .screenshot("ScreenshotResults"),

    .section("The Journal"),
    .paragraph("The journal keeps a cumulative record of every recognized change found across all your comparisons. Switch to it by clicking **Journal** in the segmented control at the top of the SetShot window."),
    .paragraph("Journal entries are grouped by comparison, with a header showing the date and time of the comparison and how many recognized changes it found. Each entry shows the setting description, its location in System Settings, and the before and after values. An **Open in Settings** button appears when possible."),
    .paragraph("To add a personal note to any entry, click **Add note…** at the bottom of the row and type. Your note is saved automatically when you click away."),
    .paragraph("Use the search field at the top to filter entries by description, setting name, or location. Control-click an entry to delete it, or Control-click a section header to remove all entries from that comparison at once. Click **Export HTML…** to save the entire journal as an HTML file, or **Clear All** to permanently delete all entries (you'll be asked to confirm)."),
    .paragraph("The journal automatically eliminates redundant entries: if the same change appears more than once \u{2014} for instance, if you run the same comparison twice \u{2014} only the earliest occurrence is kept."),
    .screenshot("ScreenshotJournal"),

    .section("Submitting Unrecognized Changes"),
    .paragraph("When you find an unrecognized change that is either noise or that you think should be included in the knowledge base, click **Submit** on that row. A confirmation sheet shows exactly what data will be sent \u{2014} the internal setting name, its old and new values, and your macOS version \u{2014} and nothing else."),
    .paragraph("The sheet also offers an optional feedback section. If you have a sense of what the change represents, select one of the two categories:"),
    .callout(label: "Expected settings change",
             content: "The change reflects something real \u{2014} a preference you set, a feature you turned on, or a setting macOS adjusted as a result of something you did."),
    .callout(label: "Likely macOS noise",
             content: "The change appears to be an internal macOS value that fluctuates on its own, unrelated to any setting you'd want to track."),
    .paragraph("You can also add a short note with any context that might help with review. Both fields are entirely optional, but adding context may help categorize the change more accurately."),
    .screenshot("ScreenshotSubmitUnrecognized"),
    .paragraph("If you have several unrecognized changes, click **Submit All** to review and send them all at once. Submitted changes are reviewed, added to the knowledge base, and loaded on the next launch, making SetShot more useful for everyone."),
    .paragraph("Already-submitted rows are marked with a checkmark for the duration of the session."),

    .section("Improving Recognized Changes"),
    .paragraph("Even recognized changes can have room for improvement: an icon may be missing, a description may be unclear, a System Settings path may be wrong, or values may show as raw numbers instead of readable labels."),
    .paragraph("Click **Submit Feedback** on any recognized change row to open a feedback sheet. Check the issues that apply, add any notes that might help, and click **Submit**. The sheet shows a summary of the current description and location so you can refer to them while writing."),
    .screenshot("ScreenshotSubmitRecognized"),
    .paragraph("Feedback is reviewed by the developer and incorporated into future knowledge base updates, making SetShot more accurate for everyone."),

    .section("Automatic Snapshots"),
    .paragraph("SetShot can take snapshots automatically on a schedule. Click **Settings** in the segmented control at the top, then select **Take automatic snapshots** and choose how often: every N minutes, every N hours, once a day, once a week, or once a month. For day, week, and month intervals, you can also set the time of day."),
    .paragraph("Automatic snapshots are taken silently in the background without SetShot's window appearing. This lets you build up a history of your Mac's settings over time without having to remember to capture manually."),
    .paragraph("When you enable automatic snapshots, macOS will ask for **Notifications** permission. If granted, a notification appears whenever a scheduled snapshot finds recognized changes; clicking it opens the comparison in SetShot."),
    .paragraph("Enable **Delete scheduled snapshots with no changes** to automatically remove snapshots taken by the scheduler that found no changes, keeping your library uncluttered."),
    .screenshot("ScreenshotSettings"),

    .section("Optional Permissions"),
    .paragraph("By default, SetShot takes snapshots without requesting any special permissions. Two optional data sources in **Settings \u{2192} Optional Data Sources** expand what SetShot captures:"),
    .callout(label: "Music App Settings",
             content: "When enabled, SetShot reads Music, Home Sharing, and related preferences. macOS will display a **Media & Apple Music** permission dialog the first time a snapshot runs \u{2014} click **Allow**. This permission is remembered permanently."),
    .screenshot("PermissionMusicAccess"),
    .callout(label: "App Privacy Permissions",
             content: "When enabled, SetShot reads the system privacy database to detect which apps have been granted access to the microphone, camera, contacts, and similar resources. This requires **Full Disk Access** \u{2014} grant it in **System Settings \u{2192} Privacy & Security \u{2192} Full Disk Access**, or use the button in Settings \u{2192} Optional Data Sources."),
    .paragraph("One more permission is used when automatic snapshots are enabled:"),
    .callout(label: "Notifications",
             content: "When you enable automatic snapshots in Settings, macOS will ask for Notifications permission. If granted, a notification appears whenever a scheduled snapshot finds recognized changes; clicking it opens the comparison."),

    .section("Privacy"),
    .paragraph("The data SetShot works with is inherently non-sensitive \u{2014} it's system settings like toggles, sliders, and preferences, not passwords, documents, photos, or personal content. That said, SetShot is designed to keep your data private."),
    .bullet("**Snapshots, comparisons, and journal entries** are stored only on this Mac and are never transmitted anywhere."),
    .bullet("**Submissions** are the one exception. When you submit an unrecognized change or send feedback on a recognized change, the relevant setting data is sent to the developer over a secure connection and stored privately. Submissions are entirely opt-in. As with any Internet connection, your IP address is seen by the service that handles submissions (Cloudflare) but is not stored in your submission record."),
    .paragraph("SetShot is open source. If you want to verify exactly what data the app collects and how it is handled, the full source code is available at [github.com/adamengst/setshot-app](https://github.com/adamengst/setshot-app)."),

    .section("What\u{2019}s New in 1.0b18"),
    .bullet("**Journal notes** \u{2014} Click **Add note\u{2026}** at the bottom of any journal entry to add a personal annotation. Notes save automatically and appear in HTML exports."),
    .bullet("**Journal HTML export** \u{2014} Click **Export HTML\u{2026}** next to **Clear All** to save the entire journal as a portable HTML file."),
    .bullet("**More recognized settings** \u{2014} Added Bluetooth Sharing (file receiving behavior, remote browsing permissions), Content Caching (cache size in GB, cache location, Share Internet Connection), Remote Login (Allow Full Disk Access for Remote Users), and Internet Sharing (source and target interfaces) to the knowledge base."),
    .bullet("**Selectable text** \u{2014} Text in the About view and the About SetShot dialog can now be selected and copied."),
    .bullet("**Desktop Mac improvements** \u{2014} Battery-specific settings (Battery Power sleep timers, charge limit, battery menu bar icon, etc.) no longer appear as recognized changes on desktop Macs without a battery."),
]

/// Renders the entire help document as a single selectable NSTextView so the
/// user can select and copy text spanning multiple paragraphs in one drag.
/// Screenshots are embedded inline as NSTextAttachments.
private struct AboutHelpNSTextView: NSViewRepresentable {
    let content: [HelpContent]

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        guard let tv = scroll.documentView as? NSTextView else { return scroll }
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 40, height: 40)
        tv.isAutomaticLinkDetectionEnabled = true
        tv.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .cursor: NSCursor.pointingHand
        ]
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        tv.textStorage?.setAttributedString(Self.buildAttributedString(content))
    }

    private static func append(_ result: NSMutableAttributedString,
                               markdown: String,
                               baseFont: NSFont,
                               baseColor: NSColor,
                               paragraph: NSParagraphStyle) {
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        let attr = (try? AttributedString(markdown: markdown, options: opts)) ?? AttributedString(markdown)
        let fontSize = baseFont.pointSize
        for run in attr.runs {
            let chars = String(attr[run.range].characters)
            let intent = run.inlinePresentationIntent
            let isBold = intent?.contains(.stronglyEmphasized) == true
            let isCode = intent?.contains(.code) == true
            let font: NSFont
            if isCode {
                font = .monospacedSystemFont(ofSize: fontSize - 1, weight: .regular)
            } else if isBold {
                font = .systemFont(ofSize: fontSize, weight: .bold)
            } else {
                font = baseFont
            }
            var attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: baseColor,
                .paragraphStyle: paragraph
            ]
            if let link = run.link {
                attrs[.link] = link
                attrs[.foregroundColor] = NSColor.linkColor
            }
            result.append(NSAttributedString(string: chars, attributes: attrs))
        }
    }

    static func buildAttributedString(_ content: [HelpContent]) -> NSAttributedString {
        let result = NSMutableAttributedString()

        func paragraphStyle(spacingBefore: CGFloat, spacingAfter: CGFloat, bulletIndent: Bool = false) -> NSParagraphStyle {
            let p = NSMutableParagraphStyle()
            p.paragraphSpacingBefore = spacingBefore
            p.paragraphSpacing = spacingAfter
            p.lineSpacing = 2
            if bulletIndent {
                p.headIndent = 16
                p.firstLineHeadIndent = 0
                p.tabStops = [NSTextTab(textAlignment: .left, location: 16)]
            }
            return p
        }

        func newlineIfNeeded() {
            if result.length > 0 {
                result.append(NSAttributedString(string: "\n"))
            }
        }

        for item in content {
            switch item {
            case .title(let text):
                newlineIfNeeded()
                append(result, markdown: text,
                       baseFont: .systemFont(ofSize: 28, weight: .bold),
                       baseColor: .labelColor,
                       paragraph: paragraphStyle(spacingBefore: 0, spacingAfter: 12))

            case .intro(let text):
                newlineIfNeeded()
                append(result, markdown: text,
                       baseFont: .systemFont(ofSize: 14, weight: .regular),
                       baseColor: .labelColor,
                       paragraph: paragraphStyle(spacingBefore: 0, spacingAfter: 12))

            case .section(let text):
                newlineIfNeeded()
                append(result, markdown: text,
                       baseFont: .systemFont(ofSize: 22, weight: .semibold),
                       baseColor: .labelColor,
                       paragraph: paragraphStyle(spacingBefore: 24, spacingAfter: 10))

            case .paragraph(let text):
                newlineIfNeeded()
                append(result, markdown: text,
                       baseFont: .systemFont(ofSize: 14, weight: .regular),
                       baseColor: .labelColor,
                       paragraph: paragraphStyle(spacingBefore: 0, spacingAfter: 12))

            case .bullet(let text):
                newlineIfNeeded()
                let style = paragraphStyle(spacingBefore: 0, spacingAfter: 6, bulletIndent: true)
                append(result, markdown: "\u{2022}\t" + text,
                       baseFont: .systemFont(ofSize: 14, weight: .regular),
                       baseColor: .labelColor,
                       paragraph: style)

            case .callout(let label, let content):
                newlineIfNeeded()
                append(result, markdown: label,
                       baseFont: .systemFont(ofSize: 14, weight: .semibold),
                       baseColor: .labelColor,
                       paragraph: paragraphStyle(spacingBefore: 6, spacingAfter: 2))
                result.append(NSAttributedString(string: "\n"))
                append(result, markdown: content,
                       baseFont: .systemFont(ofSize: 14, weight: .regular),
                       baseColor: .secondaryLabelColor,
                       paragraph: paragraphStyle(spacingBefore: 0, spacingAfter: 12))

            case .screenshot(let name):
                if let img = NSImage(named: name) {
                    newlineIfNeeded()
                    let attachment = NSTextAttachment()
                    let scaled = NSSize(width: img.size.width / 2, height: img.size.height / 2)
                    attachment.image = img
                    attachment.bounds = CGRect(origin: .zero, size: scaled)
                    let imgStr = NSMutableAttributedString(attachment: attachment)
                    let p = NSMutableParagraphStyle()
                    p.paragraphSpacingBefore = 4
                    p.paragraphSpacing = 12
                    imgStr.addAttribute(.paragraphStyle,
                                        value: p,
                                        range: NSRange(location: 0, length: imgStr.length))
                    result.append(imgStr)
                }
            }
        }
        return result
    }
}

// MARK: - About view

struct AboutView: View {
    @State private var searchQuery = ""
    @State private var matchIndex = 0

    private var matches: [String] {
        guard !searchQuery.isEmpty else { return [] }
        let q = searchQuery.lowercased()
        var result: [String] = []
        for (id, text) in Self.searchNodes {
            let lower = text.lowercased()
            var pos = lower.startIndex
            while let r = lower.range(of: q, range: pos..<lower.endIndex) {
                result.append(id)
                pos = r.upperBound
            }
        }
        return result
    }

    private var activeNodeId: String {
        guard !matches.isEmpty, matchIndex < matches.count else { return "" }
        return matches[matchIndex]
    }

    private var activeOccurrenceIndex: Int {
        guard !matches.isEmpty, matchIndex < matches.count else { return -1 }
        let nodeId = matches[matchIndex]
        return matches[..<matchIndex].filter { $0 == nodeId }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            if searchQuery.isEmpty {
                // Non-search path: a single selectable NSTextView so text can be
                // selected and copied across paragraphs in one drag.
                AboutHelpNSTextView(content: aboutHelpContent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 32) {
                            intro.id("about-intro")
                            setShotViews
                            takingSnapshots
                            comparingSnapshots
                            understandingResults
                            theJournal
                            submittingChanges
                            improvingRecognized
                            automaticSnapshots
                            permissions
                            privacy
                            releaseNotes
                        }
                        .environment(\.aboutSearchQuery, searchQuery)
                        .environment(\.aboutActiveNodeId, activeNodeId)
                        .environment(\.aboutActiveOccurrence, activeOccurrenceIndex)
                        .font(.system(size: 14))
                        .padding(40)
                    }
                    .frame(maxWidth: .infinity)
                    .onChange(of: matchIndex) { [self] _ in scroll(to: matchIndex, proxy: proxy) }
                    .onChange(of: searchQuery) { [self] _ in
                        matchIndex = 0
                        scroll(to: 0, proxy: proxy)
                    }
                }
            }
        }
    }

    private func scroll(to index: Int, proxy: ScrollViewProxy) {
        guard !matches.isEmpty, index < matches.count else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            proxy.scrollTo(matches[index], anchor: .top)
        }
    }

    private func nextMatch() {
        guard !matches.isEmpty else { return }
        matchIndex = (matchIndex + 1) % matches.count
    }

    private func prevMatch() {
        guard !matches.isEmpty else { return }
        matchIndex = (matchIndex - 1 + matches.count) % matches.count
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search", text: $searchQuery)
                .textFieldStyle(.plain)
            if !searchQuery.isEmpty {
                if matches.isEmpty {
                    Text("No results")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    Text("\(matchIndex + 1) of \(matches.count)")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                        .monospacedDigit()
                    Button(action: prevMatch) {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.plain)
                    Button(action: nextMatch) {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.plain)
                }
                Button { searchQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Sections

    private var intro: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About SetShot")
                .font(.largeTitle)
                .fontWeight(.bold)
            HelpParagraph("Have you ever thought a macOS update changed some setting silently? Or have you spelunked through System Settings and wondered later what you clicked? With SetShot, you can find out what settings have changed over time, making it easy to see what you've done and revert inadvertent changes.",
                          id: "n-intro-0")
            HelpParagraph("SetShot lets you capture a complete snapshot of your Mac's settings at any point in time so you can compare any two snapshots and see exactly what changed, in plain English. Each recognized change comes with a description, its location in System Settings, and \u{2014} where possible \u{2014} a button that opens the exact pane directly.",
                          id: "n-intro-1")
        }
    }

    private var setShotViews: some View {
        HelpSection("SetShot Views", id: "about-views") {
            HelpParagraph("SetShot has four views, accessed by clicking the buttons at the top of the window:",
                          id: "n-views-0")
            screenshot("ScreenshotNavigation")
            VStack(alignment: .leading, spacing: 6) {
                HelpBullet("**Snapshots:** Shows all the snapshots you've taken in Before and After columns.",
                           id: "n-views-b0")
                HelpBullet("**Journal:** A chronological log of all recognized changes across your comparisons.",
                           id: "n-views-b1")
                HelpBullet("**Settings:** Reverse sort order and set up automatic daily snapshots.",
                           id: "n-views-b2")
                HelpBullet("**About:** You're reading it now.",
                           id: "n-views-b3")
            }
        }
    }

    private var takingSnapshots: some View {
        HelpSection("Taking Snapshots", id: "about-taking") {
            HelpParagraph("SetShot's core function is to take and compare snapshots. To that end, it scans nearly 500 settings files across more than a dozen system data sources. It currently recognizes over 400 settings and knows to ignore over 50 additional changes that are just macOS noise.",
                          id: "n-taking-0")
            HelpParagraph("To take a snapshot of the current state of your Mac's settings, click **Take Snapshot** at the bottom of the Snapshots view. SetShot saves the result to the snapshot library with the date and time. Snapshots are stored in `~/Library/Application Support/SetShot/snapshots` as gzipped files that occupy little space. Capturing typically takes less than a minute.",
                          id: "n-taking-1")
            screenshot("ScreenshotSnapshotsContext")
            HelpParagraph("Each snapshot line shows the number of recognized changes from the previous snapshot and the size of the snapshot file.",
                          id: "n-taking-2")
            HelpParagraph("To rename a snapshot, Control-click it and choose **Rename**, then type a new name. Renaming can be useful for labelling snapshots with context \u{2014} for example, \u{2018}Before macOS 26.6\u{2019} or \u{2018}After Accessibility testing.\u{2019}",
                          id: "n-taking-3")
            HelpParagraph("To remove an unnecessary snapshot, Control-click it and choose **Delete**.",
                          id: "n-taking-4")
        }
    }

    private var comparingSnapshots: some View {
        HelpSection("Comparing Snapshots", id: "about-comparing") {
            HelpParagraph("Once you've taken at least two snapshots, you can use SetShot to compare them.",
                          id: "n-comparing-0")
            HelpParagraph("The Snapshots view shows two columns. Click a snapshot in the left column to set it as the **Before** snapshot, and click a snapshot in the right column to set it as the **After** snapshot.",
                          id: "n-comparing-1")
            screenshot("ScreenshotSnapshotsReady")
            HelpParagraph("Once you have selected both snapshots, click **Compare** to run the comparison. The results open in a new window titled with the names of the two snapshots, leaving the snapshot library available so you can start additional comparisons. You can have multiple comparison windows open at once to look at them side by side.",
                          id: "n-comparing-2")
            HelpParagraph("SetShot identifies every setting that differs between the two snapshots and looks up each one in its knowledge base to determine whether it's a recognized change or an unrecognized change. Changes to the knowledge base are read at every launch.",
                          id: "n-comparing-3")
        }
    }

    private var understandingResults: some View {
        HelpSection("Understanding Results", id: "about-results") {
            HelpParagraph("Results are divided into two sections:",
                          id: "n-results-0")
            HelpCallout("Recognized Changes",
                content: "Settings already in SetShot\u{2019}s knowledge base. Each entry shows a plain-English description, the path to find it in System Settings, and \u{2014} where possible \u{2014} an **Open in Settings** button that takes you directly to the relevant pane. The old value appears in orange and the new value in blue. A **Submit Feedback** button lets you flag issues with the description, path, icon, or value formatting to help improve SetShot for everyone.",
                id: "n-results-c0")
            HelpCallout("Unrecognized Changes",
                content: "Changes that are either noise or legitimate settings changes that aren't yet in the knowledge base. The raw technical name of the setting is shown along with its old and new values. You can submit these to help improve SetShot for everyone.",
                id: "n-results-c1")
            HelpParagraph("Values are displayed in a readable form where possible: toggles show On or Off, volume settings show a percentage, file paths show just the filename, and settings with a fixed list of options (like Hot Corner actions) show the option name rather than a raw number.",
                          id: "n-results-1")
            screenshot("ScreenshotResults")
        }
    }

    private var theJournal: some View {
        HelpSection("The Journal", id: "about-journal") {
            HelpParagraph("The journal keeps a cumulative record of every recognized change found across all your comparisons. Switch to it by clicking **Journal** in the segmented control at the top of the SetShot window.",
                          id: "n-journal-0")
            HelpParagraph("Journal entries are grouped by comparison, with a header showing the date and time of the comparison and how many recognized changes it found. Each entry shows the setting description, its location in System Settings, and the before and after values. An **Open in Settings** button appears when possible.",
                          id: "n-journal-1")
            HelpParagraph("To add a personal note to any entry, click **Add note\u{2026}** at the bottom of the row and type. Your note is saved automatically when you click away.",
                          id: "n-journal-2")
            HelpParagraph("Use the search field at the top to filter entries by description, setting name, or location. Control-click an entry to delete it, or Control-click a section header to remove all entries from that comparison at once. Click **Export HTML\u{2026}** to save the entire journal as an HTML file, or **Clear All** to permanently delete all entries (you\u{2019}ll be asked to confirm).",
                          id: "n-journal-3")
            HelpParagraph("The journal automatically eliminates redundant entries: if the same change appears more than once \u{2014} for instance, if you run the same comparison twice \u{2014} only the earliest occurrence is kept.",
                          id: "n-journal-4")
            screenshot("ScreenshotJournal")
        }
    }

    private var submittingChanges: some View {
        HelpSection("Submitting Unrecognized Changes", id: "about-submitting") {
            HelpParagraph("When you find an unrecognized change that is either noise or that you think should be included in the knowledge base, click **Submit** on that row. A confirmation sheet shows exactly what data will be sent \u{2014} the internal setting name, its old and new values, and your macOS version \u{2014} and nothing else.",
                          id: "n-submitting-0")
            HelpParagraph("The sheet also offers an optional feedback section. If you have a sense of what the change represents, select one of the two categories:",
                          id: "n-submitting-1")
            HelpCallout("Expected settings change",
                content: "The change reflects something real \u{2014} a preference you set, a feature you turned on, or a setting macOS adjusted as a result of something you did.",
                id: "n-submitting-c0")
            HelpCallout("Likely macOS noise",
                content: "The change appears to be an internal macOS value that fluctuates on its own, unrelated to any setting you'd want to track.",
                id: "n-submitting-c1")
            HelpParagraph("You can also add a short note with any context that might help with review. Both fields are entirely optional, but adding context may help categorize the change more accurately.",
                          id: "n-submitting-2")
            screenshot("ScreenshotSubmitUnrecognized")
            HelpParagraph("If you have several unrecognized changes, click **Submit All** to review and send them all at once. Submitted changes are reviewed, added to the knowledge base, and loaded on the next launch, making SetShot more useful for everyone.",
                          id: "n-submitting-3")
            HelpParagraph("Already-submitted rows are marked with a checkmark for the duration of the session.",
                          id: "n-submitting-4")
        }
    }

    private var improvingRecognized: some View {
        HelpSection("Improving Recognized Changes", id: "about-improving") {
            HelpParagraph("Even recognized changes can have room for improvement: an icon may be missing, a description may be unclear, a System Settings path may be wrong, or values may show as raw numbers instead of readable labels.",
                          id: "n-improving-0")
            HelpParagraph("Click **Submit Feedback** on any recognized change row to open a feedback sheet. Check the issues that apply, add any notes that might help, and click **Submit**. The sheet shows a summary of the current description and location so you can refer to them while writing.",
                          id: "n-improving-1")
            screenshot("ScreenshotSubmitRecognized")
            HelpParagraph("Feedback is reviewed by the developer and incorporated into future knowledge base updates, making SetShot more accurate for everyone.",
                          id: "n-improving-2")
        }
    }

    private var automaticSnapshots: some View {
        HelpSection("Automatic Snapshots", id: "about-automatic") {
            HelpParagraph("SetShot can take snapshots automatically on a schedule. Click **Settings** in the segmented control at the top, then select **Take automatic snapshots** and choose how often: every N minutes, every N hours, once a day, once a week, or once a month. For day, week, and month intervals, you can also set the time of day.",
                          id: "n-automatic-0")
            HelpParagraph("Automatic snapshots are taken silently in the background without SetShot's window appearing. This lets you build up a history of your Mac's settings over time without having to remember to capture manually.",
                          id: "n-automatic-1")
            HelpParagraph("When you enable automatic snapshots, macOS will ask for **Notifications** permission. If granted, a notification appears whenever a scheduled snapshot finds recognized changes; clicking it opens the comparison in SetShot.",
                          id: "n-automatic-2")
            HelpParagraph("Enable **Delete scheduled snapshots with no changes** to automatically remove snapshots taken by the scheduler that found no changes, keeping your library uncluttered.",
                          id: "n-automatic-3")
            screenshot("ScreenshotSettings")
        }
    }

    private var permissions: some View {
        HelpSection("Optional Permissions", id: "about-permissions") {
            HelpParagraph("By default, SetShot takes snapshots without requesting any special permissions. Two optional data sources in **Settings \u{2192} Optional Data Sources** expand what SetShot captures:",
                          id: "n-permissions-0")
            HelpCallout("Music App Settings",
                content: "When enabled, SetShot reads Music, Home Sharing, and related preferences. macOS will display a **Media & Apple Music** permission dialog the first time a snapshot runs \u{2014} click **Allow**. This permission is remembered permanently.",
                id: "n-permissions-c0")
            screenshot("PermissionMusicAccess")
            HelpCallout("App Privacy Permissions",
                content: "When enabled, SetShot reads the system privacy database to detect which apps have been granted access to the microphone, camera, contacts, and similar resources. This requires **Full Disk Access** \u{2014} grant it in **System Settings \u{2192} Privacy & Security \u{2192} Full Disk Access**, or use the button in Settings \u{2192} Optional Data Sources.",
                id: "n-permissions-c1")
            HelpParagraph("One more permission is used when automatic snapshots are enabled:",
                          id: "n-permissions-1")
            HelpCallout("Notifications",
                content: "When you enable automatic snapshots in Settings, macOS will ask for Notifications permission. If granted, a notification appears whenever a scheduled snapshot finds recognized changes; clicking it opens the comparison.",
                id: "n-permissions-c2")
        }
    }

    private var releaseNotes: some View {
        HelpSection("What\u{2019}s New in 1.0b18", id: "about-relnotes") {
            HelpBullet("**Journal notes** \u{2014} Click **Add note\u{2026}** at the bottom of any journal entry to add a personal annotation. Notes save automatically and appear in HTML exports.",
                       id: "n-relnotes-b0")
            HelpBullet("**Journal HTML export** \u{2014} Click **Export HTML\u{2026}** next to **Clear All** to save the entire journal as a portable HTML file.",
                       id: "n-relnotes-b1")
            HelpBullet("**More recognized settings** \u{2014} Added Bluetooth Sharing (file receiving behavior, remote browsing permissions), Content Caching (cache size in GB, cache location, Share Internet Connection), Remote Login (Allow Full Disk Access for Remote Users), and Internet Sharing (source and target interfaces) to the knowledge base.",
                       id: "n-relnotes-b2")
            HelpBullet("**Selectable text** \u{2014} Text in the About view and the About SetShot dialog can now be selected and copied.",
                       id: "n-relnotes-b3")
            HelpBullet("**Desktop Mac improvements** \u{2014} Battery-specific settings (Battery Power sleep timers, charge limit, battery menu bar icon, etc.) no longer appear as recognized changes on desktop Macs without a battery.",
                       id: "n-relnotes-b4")
        }
    }

    private var privacy: some View {
        HelpSection("Privacy", id: "about-privacy") {
            HelpParagraph("The data SetShot works with is inherently non-sensitive \u{2014} it's system settings like toggles, sliders, and preferences, not passwords, documents, photos, or personal content. That said, SetShot is designed to keep your data private.",
                          id: "n-privacy-0")
            HelpBullet("**Snapshots, comparisons, and journal entries** are stored only on this Mac and are never transmitted anywhere.",
                       id: "n-privacy-b0")
            HelpBullet("**Submissions** are the one exception. When you submit an unrecognized change or send feedback on a recognized change, the relevant setting data is sent to the developer over a secure connection and stored privately. Submissions are entirely opt-in. As with any Internet connection, your IP address is seen by the service that handles submissions (Cloudflare) but is not stored in your submission record.",
                       id: "n-privacy-b1")
            HelpParagraph("SetShot is open source. If you want to verify exactly what data the app collects and how it is handled, the full source code is available at [github.com/adamengst/setshot-app](https://github.com/adamengst/setshot-app).",
                          id: "n-privacy-1")
        }
    }

    @ViewBuilder
    private func screenshot(_ name: String) -> some View {
        if let nsImage = NSImage(named: name) {
            Image(nsImage: nsImage)
                .resizable()
                .frame(width: nsImage.size.width / 2, height: nsImage.size.height / 2)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        }
    }

    // MARK: - Search corpus

    private static let searchNodes: [(id: String, text: String)] = [
        // intro
        ("about-intro",   "About SetShot"),
        ("n-intro-0",     "Have you ever thought a macOS update changed some setting silently? Or have you spelunked through System Settings and wondered later what you clicked? With SetShot, you can find out what settings have changed over time, making it easy to see what you've done and revert inadvertent changes."),
        ("n-intro-1",     "SetShot lets you capture a complete snapshot of your Mac's settings at any point in time so you can compare any two snapshots and see exactly what changed, in plain English. Each recognized change comes with a description, its location in System Settings, and \u{2014} where possible \u{2014} a button that opens the exact pane directly."),
        // SetShot Views
        ("about-views",   "SetShot Views"),
        ("n-views-0",     "SetShot has four views, accessed by clicking the buttons at the top of the window:"),
        ("n-views-b0",    "Snapshots: Shows all the snapshots you've taken in Before and After columns."),
        ("n-views-b1",    "Journal: A chronological log of all recognized changes across your comparisons."),
        ("n-views-b2",    "Settings: Reverse sort order and set up automatic daily snapshots."),
        ("n-views-b3",    "About: You're reading it now."),
        // Taking Snapshots
        ("about-taking",  "Taking Snapshots"),
        ("n-taking-0",    "SetShot's core function is to take and compare snapshots. To that end, it scans nearly 500 settings files across more than a dozen system data sources. It currently recognizes over 400 settings and knows to ignore over 50 additional changes that are just macOS noise."),
        ("n-taking-1",    "To take a snapshot of the current state of your Mac's settings, click Take Snapshot at the bottom of the Snapshots view. SetShot saves the result to the snapshot library with the date and time. Snapshots are stored in ~/Library/Application Support/SetShot/snapshots as gzipped files that occupy little space. Capturing typically takes less than a minute."),
        ("n-taking-2",    "Each snapshot line shows the number of recognized changes from the previous snapshot and the size of the snapshot file."),
        ("n-taking-3",    "To rename a snapshot, Control-click it and choose Rename, then type a new name. Renaming can be useful for labelling snapshots with context \u{2014} for example, \u{2018}Before macOS 26.6\u{2019} or \u{2018}After Accessibility testing.\u{2019}"),
        ("n-taking-4",    "To remove an unnecessary snapshot, Control-click it and choose Delete."),
        // Comparing Snapshots
        ("about-comparing", "Comparing Snapshots"),
        ("n-comparing-0",   "Once you've taken at least two snapshots, you can use SetShot to compare them."),
        ("n-comparing-1",   "The Snapshots view shows two columns. Click a snapshot in the left column to set it as the Before snapshot, and click a snapshot in the right column to set it as the After snapshot."),
        ("n-comparing-2",   "Once you have selected both snapshots, click Compare to run the comparison. The results open in a new window titled with the names of the two snapshots, leaving the snapshot library available so you can start additional comparisons. You can have multiple comparison windows open at once to look at them side by side."),
        ("n-comparing-3",   "SetShot identifies every setting that differs between the two snapshots and looks up each one in its knowledge base to determine whether it's a recognized change or an unrecognized change. Changes to the knowledge base are read at every launch."),
        // Understanding Results
        ("about-results", "Understanding Results"),
        ("n-results-0",   "Results are divided into two sections:"),
        ("n-results-c0",  "Recognized Changes Settings already in SetShot's knowledge base. Each entry shows a plain-English description, the path to find it in System Settings, and \u{2014} where possible \u{2014} an Open in Settings button that takes you directly to the relevant pane. The old value appears in orange and the new value in blue. A Submit Feedback button lets you flag issues with the description, path, icon, or value formatting to help improve SetShot for everyone."),
        ("n-results-c1",  "Unrecognized Changes Changes that are either noise or legitimate settings changes that aren't yet in the knowledge base. The raw technical name of the setting is shown along with its old and new values. You can submit these to help improve SetShot for everyone."),
        ("n-results-1",   "Values are displayed in a readable form where possible: toggles show On or Off, volume settings show a percentage, file paths show just the filename, and settings with a fixed list of options (like Hot Corner actions) show the option name rather than a raw number."),
        // The Journal
        ("about-journal", "The Journal"),
        ("n-journal-0",   "The journal keeps a cumulative record of every recognized change found across all your comparisons. Switch to it by clicking Journal in the segmented control at the top of the SetShot window."),
        ("n-journal-1",   "Journal entries are grouped by comparison, with a header showing the date and time of the comparison and how many recognized changes it found. Each entry shows the setting description, its location in System Settings, and the before and after values. An Open in Settings button appears when possible."),
        ("n-journal-2",   "To add a personal note to any entry, click Add note\u{2026} at the bottom of the row and type. Your note is saved automatically when you click away."),
        ("n-journal-3",   "Use the search field at the top to filter entries by description, setting name, or location. Control-click an entry to delete it, or Control-click a section header to remove all entries from that comparison at once. Click Export HTML\u{2026} to save the entire journal as an HTML file, or Clear All to permanently delete all entries."),
        ("n-journal-4",   "The journal automatically eliminates redundant entries: if the same change appears more than once \u{2014} for instance, if you run the same comparison twice \u{2014} only the earliest occurrence is kept."),
        // Submitting Unrecognized Changes
        ("about-submitting", "Submitting Unrecognized Changes"),
        ("n-submitting-0",   "When you find an unrecognized change that is either noise or that you think should be included in the knowledge base, click Submit on that row. A confirmation sheet shows exactly what data will be sent \u{2014} the internal setting name, its old and new values, and your macOS version \u{2014} and nothing else."),
        ("n-submitting-1",   "The sheet also offers an optional feedback section. If you have a sense of what the change represents, select one of the two categories:"),
        ("n-submitting-c0",  "Expected settings change The change reflects something real \u{2014} a preference you set, a feature you turned on, or a setting macOS adjusted as a result of something you did."),
        ("n-submitting-c1",  "Likely macOS noise The change appears to be an internal macOS value that fluctuates on its own, unrelated to any setting you'd want to track."),
        ("n-submitting-2",   "You can also add a short note with any context that might help with review. Both fields are entirely optional, but adding context may help categorize the change more accurately."),
        ("n-submitting-3",   "If you have several unrecognized changes, click Submit All to review and send them all at once. Submitted changes are reviewed, added to the knowledge base, and loaded on the next launch, making SetShot more useful for everyone."),
        ("n-submitting-4",   "Already-submitted rows are marked with a checkmark for the duration of the session."),
        // Improving Recognized Changes
        ("about-improving", "Improving Recognized Changes"),
        ("n-improving-0",   "Even recognized changes can have room for improvement: an icon may be missing, a description may be unclear, a System Settings path may be wrong, or values may show as raw numbers instead of readable labels."),
        ("n-improving-1",   "Click Submit Feedback on any recognized change row to open a feedback sheet. Check the issues that apply, add any notes that might help, and click Submit. The sheet shows a summary of the current description and location so you can refer to them while writing."),
        ("n-improving-2",   "Feedback is reviewed by the developer and incorporated into future knowledge base updates, making SetShot more accurate for everyone."),
        // Automatic Snapshots
        ("about-automatic", "Automatic Snapshots"),
        ("n-automatic-0",   "SetShot can take snapshots automatically on a schedule. Click Settings in the segmented control at the top, then select Take automatic snapshots and choose how often: every N minutes, every N hours, once a day, once a week, or once a month. For day, week, and month intervals, you can also set the time of day."),
        ("n-automatic-1",   "Automatic snapshots are taken silently in the background without SetShot's window appearing. This lets you build up a history of your Mac's settings over time without having to remember to capture manually."),
        ("n-automatic-2",   "When you enable automatic snapshots, macOS will ask for Notifications permission. If granted, a notification appears whenever a scheduled snapshot finds recognized changes; clicking it opens the comparison in SetShot."),
        ("n-automatic-3",   "Enable Delete scheduled snapshots with no changes to automatically remove snapshots taken by the scheduler that found no changes, keeping your library uncluttered."),
        // Optional Permissions
        ("about-permissions", "Optional Permissions"),
        ("n-permissions-0",   "By default, SetShot takes snapshots without requesting any special permissions. Two optional data sources in Settings \u{2192} Optional Data Sources expand what SetShot captures:"),
        ("n-permissions-c0",  "Music App Settings When enabled, SetShot reads Music, Home Sharing, and related preferences. macOS will display a Media & Apple Music permission dialog the first time a snapshot runs \u{2014} click Allow. This permission is remembered permanently."),
        ("n-permissions-c1",  "App Privacy Permissions When enabled, SetShot reads the system privacy database to detect which apps have been granted access to the microphone, camera, contacts, and similar resources. This requires Full Disk Access \u{2014} grant it in System Settings \u{2192} Privacy & Security \u{2192} Full Disk Access, or use the button in Settings \u{2192} Optional Data Sources."),
        ("n-permissions-1",   "One more permission is used when automatic snapshots are enabled:"),
        ("n-permissions-c2",  "Notifications When you enable automatic snapshots in Settings, macOS will ask for Notifications permission. If granted, a notification appears whenever a scheduled snapshot finds recognized changes; clicking it opens the comparison."),
        // Privacy
        ("about-privacy", "Privacy"),
        ("n-privacy-0",   "The data SetShot works with is inherently non-sensitive \u{2014} it's system settings like toggles, sliders, and preferences, not passwords, documents, photos, or personal content. That said, SetShot is designed to keep your data private."),
        ("n-privacy-b0",  "Snapshots, comparisons, and journal entries are stored only on this Mac and are never transmitted anywhere."),
        ("n-privacy-b1",  "Submissions are the one exception. When you submit an unrecognized change or send feedback on a recognized change, the relevant setting data is sent to the developer over a secure connection and stored privately. Submissions are entirely opt-in. As with any Internet connection, your IP address is seen by the service that handles submissions (Cloudflare) but is not stored in your submission record."),
        ("n-privacy-1",   "SetShot is open source. If you want to verify exactly what data the app collects and how it is handled, the full source code is available at github.com/adamengst/setshot-app."),
        // What's New
        ("about-relnotes", "What\u{2019}s New in 1.0b18"),
        ("n-relnotes-b0",  "Journal notes \u{2014} Click Add note\u{2026} at the bottom of any journal entry to add a personal annotation. Notes save automatically and appear in HTML exports."),
        ("n-relnotes-b1",  "Journal HTML export \u{2014} Click Export HTML\u{2026} next to Clear All to save the entire journal as a portable HTML file."),
        ("n-relnotes-b2",  "More recognized settings \u{2014} Added Bluetooth Sharing, Content Caching, Remote Login Full Disk Access, and Internet Sharing interfaces to the knowledge base."),
        ("n-relnotes-b3",  "Selectable text \u{2014} Text in the About view and the About SetShot dialog can now be selected and copied."),
        ("n-relnotes-b4",  "Desktop Mac improvements \u{2014} Battery-specific settings no longer appear as recognized changes on desktop Macs without a battery."),
    ]
}

// MARK: - Layout helpers

struct HelpSection<Content: View>: View {
    let title: String
    let sectionId: String
    let content: Content
    @Environment(\.aboutSearchQuery) private var searchQuery
    @Environment(\.aboutActiveNodeId) private var activeNodeId
    @Environment(\.aboutActiveOccurrence) private var activeOccurrence

    init(_ title: String, id sectionId: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.sectionId = sectionId
        self.content = content()
    }

    var body: some View {
        let titleActive = sectionId == activeNodeId ? activeOccurrence : -1
        VStack(alignment: .leading, spacing: 10) {
            Text(highlighted(title, query: searchQuery, activeOccurrence: titleActive))
                .font(.title2)
                .fontWeight(.semibold)
            content
        }
        .id(sectionId)
    }
}

struct HelpParagraph: View {
    let text: String
    let nodeId: String
    @Environment(\.aboutSearchQuery) private var searchQuery
    @Environment(\.aboutActiveNodeId) private var activeNodeId
    @Environment(\.aboutActiveOccurrence) private var activeOccurrence

    init(_ text: String, id nodeId: String) {
        self.text = text
        self.nodeId = nodeId
    }

    var body: some View {
        let occIdx = nodeId == activeNodeId ? activeOccurrence : -1
        Text(highlighted(text, query: searchQuery, activeOccurrence: occIdx))
            .fixedSize(horizontal: false, vertical: true)
            .id(nodeId)
    }
}

struct HelpBullet: View {
    let text: String
    let nodeId: String
    @Environment(\.aboutSearchQuery) private var searchQuery
    @Environment(\.aboutActiveNodeId) private var activeNodeId
    @Environment(\.aboutActiveOccurrence) private var activeOccurrence

    init(_ text: String, id nodeId: String) {
        self.text = text
        self.nodeId = nodeId
    }

    var body: some View {
        let occIdx = nodeId == activeNodeId ? activeOccurrence : -1
        HStack(alignment: .top, spacing: 6) {
            Text("\u{2022}").foregroundStyle(.secondary)
            Text(highlighted(text, query: searchQuery, activeOccurrence: occIdx))
                .fixedSize(horizontal: false, vertical: true)
        }
        .id(nodeId)
    }
}

struct HelpCallout: View {
    let label: String
    let content: String
    let nodeId: String
    @Environment(\.aboutSearchQuery) private var searchQuery
    @Environment(\.aboutActiveNodeId) private var activeNodeId
    @Environment(\.aboutActiveOccurrence) private var activeOccurrence

    init(_ label: String, content: String, id nodeId: String) {
        self.label = label
        self.content = content
        self.nodeId = nodeId
    }

    var body: some View {
        let occIdx = nodeId == activeNodeId ? activeOccurrence : -1
        let labelCount = plainTextOccurrenceCount(label, query: searchQuery)
        let labelActive = (occIdx >= 0 && occIdx < labelCount) ? occIdx : -1
        let contentActive = (occIdx >= labelCount) ? occIdx - labelCount : -1
        VStack(alignment: .leading, spacing: 4) {
            Text(highlighted(label, query: searchQuery, activeOccurrence: labelActive))
                .fontWeight(.medium)
            Text(highlighted(content, query: searchQuery, activeOccurrence: contentActive))
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
        .id(nodeId)
    }
}
