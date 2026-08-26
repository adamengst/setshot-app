import SwiftUI

struct ResultsView: View {
    let diff: DiffResult
    let before: StoredSnapshot
    let after: StoredSnapshot
    @State private var submittedIDs: Set<UUID> = []
    @State private var feedbackSubmittedIDs: Set<String> = []
    @State private var isSubmittingAll = false
    @State private var showSubmitAllPreview = false
    @State private var submitError: String? = nil
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                if let warning = diff.limitedAccessWarning {
                    limitedAccessBanner(warning)
                }
                recognizedSection
                unrecognizedSection
            }
            .padding(32)
            .textSelection(.enabled)
            .background(GeometryReader { geo in
                Color.clear.preference(key: ContentHeightKey.self, value: geo.size.height)
            })
        }
        .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
        .navigationTitle("\(before.displayName) → \(after.displayName)")
        .background(ComparisonWindowPositioner(contentHeight: contentHeight))
        .sheet(isPresented: $showSubmitAllPreview) {
            let unsubmitted = diff.unrecognized.filter { !submittedIDs.contains($0.id) }
            SubmitAllPreviewView(
                items: unsubmitted,
                isPresented: $showSubmitAllPreview,
                onSubmit: { submitAll(unsubmitted) }
            )
        }
        .alert("Submission Failed", isPresented: Binding(
            get: { submitError != nil },
            set: { if !$0 { submitError = nil } }
        )) {
            Button("OK") { submitError = nil }
        } message: {
            Text(submitError ?? "")
        }
        .toolbar {
            if !diff.recognized.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Menu("Export") {
                        Button("HTML…") { export(.html) }
                        Button("Markdown…") { export(.markdown) }
                    }
                    // A menu is not an action, so no ellipsis; the items keep theirs
                    // because each opens a save panel. The indicator picks up the accent
                    // colour by default, which points at a control that needs no pointing at.
                    .tint(.primary)
                    .fixedSize()
                }
            }
        }
        .frame(minWidth: 600)
    }

    private func export(_ format: ExportFormat) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        panel.nameFieldStringValue = "SetShot — \(StoredSnapshot.exportComputerName) — "
            + "\(before.exportLabel) vs \(after.exportLabel).\(format.fileExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let macOSMajor = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        let text: String
        switch format {
        case .html:
            text = HTMLExporter.export(result: diff, beforeName: before.displayName,
                                       afterName: after.displayName, macOSMajor: macOSMajor)
        case .markdown:
            text = MarkdownExporter.export(result: diff, beforeName: before.displayName,
                                           afterName: after.displayName, macOSMajor: macOSMajor)
        }
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func limitedAccessBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
        .cornerRadius(8)
    }

    private var recognizedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Recognized Changes", count: diff.recognized.count)
            if diff.recognized.isEmpty {
                Text("No recognized changes.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(diff.recognized, id: \.diff.id) { item in
                    RecognizedRow(entry: item.entry, diff: item.diff,
                                  feedbackSubmittedIDs: feedbackSubmittedIDs,
                                  onMarkFeedbackSubmitted: { feedbackSubmittedIDs.insert($0) })
                }
            }
        }
    }

    private var unrecognizedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader("Unrecognized Changes", count: diff.unrecognized.count + diff.unrecognizedOverflow)
                Spacer()
                submitAllButton
            }
            if diff.unrecognized.isEmpty {
                Text("All changes were identified.")
                    .foregroundStyle(.secondary)
            } else {
                if diff.unrecognizedOverflow > 0 {
                    Text("\(diff.unrecognized.count) of \(diff.unrecognized.count + diff.unrecognizedOverflow) unrecognized changes shown. The remaining \(diff.unrecognizedOverflow) are likely from a snapshot taken before a SetShot update changed what is captured — retake your baseline snapshot to clear them.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(diff.unrecognized) { line in
                    UnrecognizedRow(
                        diff: line,
                        isSubmitted: submittedIDs.contains(line.id),
                        onMarkSubmitted: { submittedIDs.insert(line.id) }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var submitAllButton: some View {
        let unsubmitted = diff.unrecognized.filter { !submittedIDs.contains($0.id) }
        if !unsubmitted.isEmpty {
            if isSubmittingAll {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Submitting…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button("Submit All (\(unsubmitted.count))") {
                    showSubmitAllPreview = true
                }
                .controlSize(.small)
            }
        }
    }

    private func submitAll(_ items: [DiffLine]) {
        isSubmittingAll = true
        submitError = nil
        Task {
            do {
                try await SubmissionService.shared.submitBatch(items)
                for item in items { submittedIDs.insert(item.id) }
            } catch {
                submitError = error.localizedDescription
            }
            isSubmittingAll = false
        }
    }

}

func unrecognizedRowText(rawLine: String, before: String, after: String, key: String) -> some View {
    let mono = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize - 1, weight: .regular)
    func para(_ spacing: CGFloat) -> NSParagraphStyle {
        let s = NSMutableParagraphStyle(); s.paragraphSpacing = spacing; return s
    }
    let ns = NSMutableAttributedString()
    ns.append(NSAttributedString(string: rawLine, attributes: [
        .font: mono, .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: para(8),
    ]))
    let b = before.isEmpty ? "(none)" : formatValue(before, key: key)
    let a = after.isEmpty  ? "(none)" : formatValue(after,  key: key)
    ns.append(NSAttributedString(string: "\n" + b,
        attributes: [.font: mono, .foregroundColor: NSColor.systemOrange]))
    ns.append(NSAttributedString(string: "  \u{2192}  ",
        attributes: [.font: mono, .foregroundColor: NSColor.secondaryLabelColor]))
    ns.append(NSAttributedString(string: a,
        attributes: [.font: mono, .foregroundColor: NSColor.systemBlue]))
    return Text(AttributedString(ns))
        .lineSpacing(4)
        .fixedSize(horizontal: false, vertical: true)
}



/// Names for the aerial wallpapers, which are stored only as asset UUIDs.
///
/// macOS keeps the catalogue in a world-readable JSON file, so no permission is
/// needed. Read once — it is 137 entries and never changes between snapshots.
enum AerialCatalogue {
    private static let path =
        "/Library/Application Support/com.apple.idleassetsd/Customer/entries.json"

    static let namesByID: [String: String] = {
        guard let data = FileManager.default.contents(atPath: path),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let assets = root["assets"] as? [[String: Any]]
        else { return [:] }
        return assets.reduce(into: [:]) { map, asset in
            if let id = asset["id"] as? String,
               let name = asset["accessibilityLabel"] as? String {
                map[id.uppercased()] = name
            }
        }
    }()

    static func name(forAssetID id: String) -> String? {
        namesByID[id.uppercased()]
    }
}


/// The whole description for a wallpaper row, built rather than looked up.
///
/// One KB entry has to cover every key under a display, because the display's UUID
/// sits in the middle of the key and a key_prefix cannot skip it. So the specifics —
/// which display, and which aspect of its wallpaper — are composed here.
func wallpaperDescription(key: String) -> String? {
    let uuidPattern = #"[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}"#
    var rest = key
    let scope: String

    func takeDisplay(from text: String) -> (String, String)? {
        guard let r = text.range(of: uuidPattern, options: [.regularExpression, .caseInsensitive])
        else { return nil }
        let uuid = String(text[r])
        var remainder = String(text[r.upperBound...])
        if remainder.hasPrefix(".") { remainder.removeFirst() }
        return (displayName(forUUID: uuid) ?? uuid, remainder)
    }

    // A display name is one thing; "all displays" and "new displays and Spaces" are
    // several, and the sentences below have to agree with whichever it is.
    let scopeIsPlural: Bool

    if rest.hasPrefix("Spaces.") {
        // Spaces.<space>.Displays.<display>.… — the display is the second UUID. macOS
        // writes the across-Spaces default with an empty Space UUID, leaving
        // "Spaces..Displays.<display>", so an empty first segment is stepped over
        // rather than failing the whole key and dropping the row back to the generic
        // description with its raw key attached.
        var afterSpace = String(rest.dropFirst("Spaces.".count))
        if afterSpace.hasPrefix(".") {
            afterSpace.removeFirst()
        } else if let taken = takeDisplay(from: afterSpace) {
            afterSpace = taken.1
        } else {
            return nil
        }
        guard afterSpace.hasPrefix("Displays."),
              let d = takeDisplay(from: String(afterSpace.dropFirst("Displays.".count)))
        else { return nil }
        scope = d.0
        scopeIsPlural = false
        rest = d.1
    } else if rest.hasPrefix("Displays.") {
        guard let d = takeDisplay(from: String(rest.dropFirst("Displays.".count))) else { return nil }
        scope = d.0
        scopeIsPlural = false
        rest = d.1
    } else if rest.hasPrefix("AllSpacesAndDisplays.") {
        rest = String(rest.dropFirst("AllSpacesAndDisplays.".count))
        scope = "all displays"
        scopeIsPlural = true
    } else if rest.hasPrefix("SystemDefault.") {
        rest = String(rest.dropFirst("SystemDefault.".count))
        scope = "new displays and Spaces"
        scopeIsPlural = true
    } else {
        return nil
    }

    if rest == "Type" {
        return "Whether \(scope) \(scopeIsPlural ? "show" : "shows") the same image "
            + "as wallpaper and screen saver."
    }

    // Desktop, Idle and Linked share one nested shape. Linked means the wallpaper
    // image is also the screen saver, which is the "Show as screen saver" option.
    let mode = rest.prefix(while: { $0 != "." })
    let leaf = rest
        .replacingOccurrences(of: #"^(Desktop|Idle|Linked)\."#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"\[\d+\]"#, with: "", options: .regularExpression)

    if leaf == "Content.Choices.Configuration.placement" {
        return "Wallpaper placement on \(scope)."
    }
    switch mode {
    case "Idle":   return "Screen saver on \(scope)."
    case "Linked": return "Wallpaper on \(scope), also shown as its screen saver."
    default:       return "Wallpaper on \(scope)."
    }
}

/// The part of a key that says *which* thing a row is about, for entries covering
/// many keys via key_prefix — which app a permission is for, which background item.
///
/// Display UUIDs and bundle identifiers resolve to names where possible. Both are
/// identity rather than settings, and both fall back to the raw value: a snapshot
/// outlives a monitor, and an app can be uninstalled.
func rowSubject(entry: KBEntry, key: String) -> String? {
    guard let prefix = entry.keyPrefix else { return nil }   // exact match: description is specific
    var subject = key.hasPrefix(prefix) ? String(key.dropFirst(prefix.count)) : key
    guard !subject.isEmpty else { return nil }

    if let range = subject.range(of: #"[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}"#,
                                 options: [.regularExpression, .caseInsensitive]),
       let name = displayName(forUUID: String(subject[range])) {
        subject.replaceSubrange(range, with: name)
    }
    if !subject.contains("/"), !subject.contains(" "), subject.contains("."),
       let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: subject) {
        var name = FileManager.default.displayName(atPath: url.path)
        if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
        if !name.isEmpty { subject = name }
    }
    return subject
}

/// The description shown for a recognized row.
///
/// An entry matching one exact key describes itself. An entry covering many keys
/// through key_prefix does not: it needs to say which display, app or item this row
/// is about, and that belongs on the description line — SetShot has no second one.
/// Description for a change known only by its domain and key, which is how the
/// journal and the snapshot list see one.
///
/// The knowledge base may no longer cover the key: wallpaper moved from a top-level
/// Displays. path to the Spaces. path macOS keeps current, and journal entries
/// written before that still hold the old form. Composing from the key regardless
/// means those rows read the way a comparison run today would.
func rowDescription(domain: String, key: String, kb: KnowledgeBase) -> String? {
    if let entry = kb.entry(forDomain: domain, key: key) {
        return rowDescription(entry: entry, key: key)
    }
    return domain == "wallpaper" ? wallpaperDescription(key: key) : nil
}

func rowDescription(entry: KBEntry, key: String) -> String {
    if entry.domain == "wallpaper", let built = wallpaperDescription(key: key) { return built }
    let base = entry.description ?? key
    guard let subject = rowSubject(entry: entry, key: key) else {
        return base.replacingOccurrences(of: "{subject}", with: "")
    }
    // A description can place the subject itself, for entries that read better as
    // "Camera access for Safari" than as a sentence with the app appended.
    if base.contains("{subject}") {
        return base.replacingOccurrences(of: "{subject}", with: subject)
    }
    return "\(base.hasSuffix(".") ? String(base.dropLast()) : base) — \(subject)"
}

/// Maps a display's UUID to the name macOS shows for it. Only displays currently
/// attached can be named; a snapshot easily outlives a monitor.
func displayName(forUUID uuid: String) -> String? {
    for screen in NSScreen.screens {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let cfUUID = CGDisplayCreateUUIDFromDisplayID(CGDirectDisplayID(number.uint32Value))?
                  .takeRetainedValue()
        else { continue }
        guard (CFUUIDCreateString(nil, cfUUID) as String).caseInsensitiveCompare(uuid) == .orderedSame
        else { continue }
        // NSScreen calls the internal display "Built-in Retina Display"; System
        // Settings calls it "Built-in Display", and that is the name a reader is
        // looking for when they go to change the setting.
        let id = CGDirectDisplayID(number.uint32Value)
        return CGDisplayIsBuiltin(id) != 0 ? "Built-in Display" : screen.localizedName
    }
    return nil
}

func recognizedRowText(description: String, location: String?, old: String, new: String) -> some View {
    let bodyFont  = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
    let calloutFont = NSFont.systemFont(ofSize: NSFont.systemFontSize - 1)
    let monoFont  = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize - 1, weight: .regular)
    func para(_ spacing: CGFloat) -> NSParagraphStyle {
        let s = NSMutableParagraphStyle(); s.paragraphSpacing = spacing; return s
    }
    let ns = NSMutableAttributedString()
    ns.append(NSAttributedString(string: description, attributes: [
        .font: bodyFont, .paragraphStyle: para(location != nil ? 3 : 8)
    ]))
    if let location {
        ns.append(NSAttributedString(string: "\n" + location, attributes: [
            .font: calloutFont, .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: para(8)
        ]))
    }
    let oldDisplay = old.isEmpty ? "(none)" : old
    let newDisplay = new.isEmpty ? "(none)" : new
    ns.append(NSAttributedString(string: "\n" + oldDisplay,
        attributes: [.font: monoFont, .foregroundColor: NSColor.systemOrange]))
    ns.append(NSAttributedString(string: "  \u{2192}  ",
        attributes: [.font: monoFont, .foregroundColor: NSColor.secondaryLabelColor]))
    ns.append(NSAttributedString(string: newDisplay,
        attributes: [.font: monoFont, .foregroundColor: NSColor.systemBlue]))
    return Text(AttributedString(ns))
        .lineSpacing(4)
        .fixedSize(horizontal: false, vertical: true)
}

func formatValue(_ raw: String, key: String = "", valueMap: [String: String]? = nil,
                 detail: String? = nil) -> String {
    if let map = valueMap {
        // Resolve dynamic system values for Finder new window target. These read the
        // machine's own identity, which the snapshot does not record.
        //
        // PfLo/PfOt (a custom folder) resolves from `detail`, which the caller reads
        // out of the snapshot this value came from. It used to come from live
        // UserDefaults, which showed today's folder on both sides of a comparison.
        // With no detail available the value_map's "Custom folder" is used instead —
        // vague, but never wrong.
        if key == "NewWindowTarget" {
            if raw == "PfLo" || raw == "PfOt" {
                // isFileURL matters: URL(string:) happily parses a bare string as a
                // relative URL, so a malformed value would otherwise be shown as if
                // it were a folder name.
                if let detail, let url = URL(string: detail), url.isFileURL,
                   !url.lastPathComponent.isEmpty, url.lastPathComponent != "/" {
                    return url.lastPathComponent
                }
            } else if raw == "PfHm" {
                return FileManager.default.homeDirectoryForCurrentUser.lastPathComponent
            } else if raw == "PfCm" {
                return Host.current().localizedName ?? map["PfCm"] ?? "My Mac"
            } else if raw == "PfVo" {
                let rootURL = URL(fileURLWithPath: "/")
                let name = (try? rootURL.resourceValues(forKeys: [.volumeLocalizedNameKey]))?.volumeLocalizedName
                return name ?? map["PfVo"] ?? "Macintosh HD"
            }
        }
        // Normalize True/False → 1/0 for value_map lookup since FLATTEN_PY
        // converts integer 0/1 to booleans, but value_map keys use integers.
        let lookupKey = raw == "True" ? "1" : raw == "False" ? "0" : raw
        if let label = map[lookupKey] { return label }
        // For path values like /System/Library/Sounds/Morse.aiff, also try the filename stem.
        if raw.hasPrefix("/"),
           let stem = URL(string: "file://\(raw)")?.deletingPathExtension().lastPathComponent,
           let label = map[stem] { return label }
    }
    // Default handlers are recorded as bundle identifiers, and LaunchServices
    // lowercases them, so the raw value reads "com.apple.safari". Resolve the app's
    // real name. This is a live lookup, but an app's name is its identity rather
    // than a setting this comparison could be about — and an app that is no longer
    // installed falls back to the identifier, which is still the honest answer.
    if key == "handler", raw.contains("."), !raw.contains("/"), !raw.contains(" ") {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: raw) {
            // displayName is localized but keeps the ".app" extension when Finder is
            // set to show extensions.
            var name = FileManager.default.displayName(atPath: url.path)
            if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
            if !name.isEmpty { return name }
        }
    }
    switch raw.lowercased() {
    case "true", "yes", "1": return "On"
    case "false", "no", "0": return "Off"
    default: break
    }
    if raw.hasPrefix("/"), let url = URL(string: "file://\(raw)") {
        return url.deletingPathExtension().lastPathComponent
    }
    if key.hasSuffix("assetID"), let name = AerialCatalogue.name(forAssetID: raw) {
        return name
    }
    if raw.hasPrefix("file://"), let url = URL(string: raw) {
        let name = url.deletingPathExtension().lastPathComponent
        if url.path.contains("/com.apple.desktop.photos/") {
            return "Photo \(name.prefix(8))\u{2026}"
        }
        return name
    }
    if raw.hasPrefix("AppleUSBAudioEngine:") {
        let parts = raw.split(separator: ":", omittingEmptySubsequences: false)
        if parts.count >= 3 {
            let productName = String(parts[2])
            if parts.count >= 2 && parts[1] == "Apple Inc." {
                if key.contains(".output") { return "\(productName) Speakers" }
                if key.contains(".input") { return "\(productName) Microphone" }
            }
            return productName
        }
    }
    if key.localizedCaseInsensitiveContains("volume"), let f = Double(raw) {
        return "\(Int((f * 100).rounded()))%"
    }
    if key == "CacheLimit", let bytes = Int64(raw), bytes > 0 {
        return "\(bytes / 1_000_000_000) GB"
    }
    // Highlight color: "R G B ColorName" — extract just the name
    let parts = raw.split(separator: " ")
    if parts.count == 4,
       Double(parts[0]) != nil, Double(parts[1]) != nil, Double(parts[2]) != nil {
        return String(parts[3])
    }
    // Trim floats with more than 2 decimal places to 2
    if let dot = raw.firstIndex(of: ".") {
        let decimals = raw.distance(from: raw.index(after: dot), to: raw.endIndex)
        if decimals > 2, let f = Double(raw) {
            return String((f * 100).rounded() / 100)
        }
    }
    return raw
}

private struct SectionHeader: View {
    let title: String
    let count: Int

    init(_ title: String, count: Int) {
        self.title = title
        self.count = count
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title).font(.headline)
            Text("(\(count))").font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

private struct RecognizedRow: View {
    let entry: KBEntry
    let diff: DiffLine
    let feedbackSubmittedIDs: Set<String>
    let onMarkFeedbackSubmitted: (String) -> Void

    @State private var showFeedback = false

    private static let macOSMajor = ProcessInfo.processInfo.operatingSystemVersion.majorVersion

    var body: some View {
        let settingsURL = validatedSettingsURL(entry.settingsURL)
        let uiLocation = entry.effectiveUILocation(macOSMajor: Self.macOSMajor)

        HStack(alignment: .top, spacing: 12) {
            SettingsPaneIcon(settingsURL: entry.settingsURL, domain: diff.domain, iconBundleID: entry.iconBundleID)
                .padding(.top, 2)
            HStack(alignment: .top, spacing: 8) {
                recognizedRowText(
                    description: rowDescription(entry: entry, key: diff.key),
                    location: uiLocation,
                    old: formatValue(diff.beforeValue, key: diff.key,
                                     valueMap: entry.valueMap, detail: diff.beforeDetail),
                    new: formatValue(diff.afterValue, key: diff.key,
                                     valueMap: entry.valueMap, detail: diff.afterDetail)
                )
                Spacer()
                VStack(alignment: .center, spacing: 0) {
                    if let url = settingsURL {
                        Button("Open in Settings") {
                            NSWorkspace.shared.open(url)
                        }
                        .controlSize(.small)
                    }
                    Spacer(minLength: 8)
                    if feedbackSubmittedIDs.contains(entry.id) {
                        Label("Feedback Sent", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else {
                        Button("Submit Feedback") { showFeedback = true }
                            .controlSize(.small)
                            .sheet(isPresented: $showFeedback) {
                                KBFeedbackView(entry: entry, diff: diff, isPresented: $showFeedback) {
                                    onMarkFeedbackSubmitted(entry.id)
                                }
                            }
                    }
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
    }

    private func validatedSettingsURL(_ raw: String?) -> URL? {
        guard let raw,
              raw.hasPrefix("x-apple.systempreferences:"),
              !raw.contains("://"),
              !raw.contains(" ") else { return nil }
        return URL(string: raw)
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ComparisonWindowPositioner: NSViewRepresentable {
    let contentHeight: CGFloat

    func makeNSView(context: Context) -> PositionerView { PositionerView() }
    func updateNSView(_ nsView: PositionerView, context: Context) {
        nsView.contentHeight = contentHeight
        nsView.applyWhenReady()
        nsView.expandIfNeeded()
    }

    class PositionerView: NSView {
        private static var nextCascadePoint: NSPoint? = nil
        var contentHeight: CGFloat = 0
        private var windowReady = false
        private var done = false
        private var lastAppliedHeight: CGFloat = 0
        private var expandPending = false
        private var closeObserver: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, !windowReady else { return }
            windowReady = true
            window.alphaValue = 0

            closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { [weak self] _ in
                let remaining = NSApp.windows.filter { $0.title.contains("→") && $0.isVisible }
                if remaining.count <= 1 { Self.nextCascadePoint = nil }
                if let obs = self?.closeObserver { NotificationCenter.default.removeObserver(obs) }
                self?.closeObserver = nil
            }

            applyWhenReady()
        }

        func applyWhenReady() {
            guard !done, windowReady, contentHeight > 0, let window else { return }
            done = true

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, weak window] in
                guard let self, let window else { return }

                guard let main = NSApp.windows.first(where: {
                    $0 !== window && $0.isVisible && !$0.isMiniaturized && $0.title == "SetShot"
                }) else { return }

                // Position first — after this, window.screen reflects the destination display.
                let startPoint = Self.nextCascadePoint ?? NSPoint(x: main.frame.maxX + 8, y: main.frame.maxY)
                Self.nextCascadePoint = window.cascadeTopLeft(from: startPoint)

                let titleBarHeight = window.frame.height - (window.contentView?.bounds.height ?? window.frame.height)

                if let screen = window.screen ?? NSScreen.main {
                    let sf = screen.visibleFrame
                    var f = window.frame

                    // Clamp right edge within screen.
                    if f.maxX > sf.maxX { f.origin.x = sf.maxX - f.width }

                    // Cap height to the space available from the window's top edge
                    // down to the screen bottom — not the full screen height, so
                    // cascaded windows that start lower don't extend off-screen.
                    let availableH = f.maxY - sf.minY
                    let targetContentH = min(self.contentHeight + 44, max(0, availableH - titleBarHeight))
                    let newH = targetContentH + titleBarHeight
                    f.origin.y = f.maxY - newH  // keep top edge fixed
                    f.size.height = newH
                    window.setFrame(f, display: false, animate: false)
                }

                self.lastAppliedHeight = self.contentHeight

                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.15
                    window.animator().alphaValue = 1
                }
            }
        }

        func expandIfNeeded() {
            guard done, !expandPending, contentHeight > lastAppliedHeight, let window else { return }
            expandPending = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self, weak window] in
                guard let self, let window else { return }
                self.expandPending = false
                let h = self.contentHeight
                guard h > self.lastAppliedHeight else { return }
                guard let screen = window.screen ?? NSScreen.main else { return }
                let titleBarH = window.frame.height - (window.contentView?.bounds.height ?? window.frame.height)
                let sf = screen.visibleFrame
                let targetTotal = h + 44 + titleBarH
                let capped = min(targetTotal, window.frame.maxY - sf.minY)
                guard capped > window.frame.height else { return }
                var f = window.frame
                f.origin.y = f.maxY - capped
                f.size.height = capped
                window.setFrame(f, display: true, animate: true)
                self.lastAppliedHeight = h
            }
        }

        deinit {
            if let obs = closeObserver { NotificationCenter.default.removeObserver(obs) }
        }
    }
}

private struct UnrecognizedRow: View {
    let diff: DiffLine
    let isSubmitted: Bool
    let onMarkSubmitted: () -> Void
    @State private var showSheet = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            unrecognizedRowText(rawLine: diff.rawLine,
                                before: diff.beforeValue,
                                after: diff.afterValue,
                                key: diff.key)
            Spacer()
            if isSubmitted {
                Label("Submitted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                Button("Submit") { showSheet = true }
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
        .sheet(isPresented: $showSheet) {
            SubmitView(diff: diff, isPresented: $showSheet, onSubmitted: onMarkSubmitted)
        }
    }
}

