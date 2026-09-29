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

// MARK: - Selectable help content (single NSTextView)

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

            case .screenshot(let name):
                appendScreenshot(name, indented: false)

            case .indentedScreenshot(let name):
                appendScreenshot(name, indented: true)
            }
        }

        func appendScreenshot(_ name: String, indented: Bool) {
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
                if indented {
                    p.headIndent = 16
                    p.firstLineHeadIndent = 16
                }
                imgStr.addAttribute(.paragraphStyle,
                                    value: p,
                                    range: NSRange(location: 0, length: imgStr.length))
                result.append(imgStr)
            }
        }
        return result
    }
}

// MARK: - About view

struct AboutView: View {
    var openSettings: () -> Void = {}
    @State private var searchQuery = ""
    @State private var matchIndex = 0
    @FocusState private var searchFocused: Bool

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
                AboutHelpNSTextView(content: HelpDocument.content)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(HelpDocument.content.enumerated()), id: \.offset) { index, item in
                                searchItem(index, item)
                            }
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
        .overlay {
            Button("") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
            Button("") { openSettings() }
                .keyboardShortcut(",", modifiers: .command)
                .opacity(0)
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
                .focused($searchFocused)
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
        // Escape clears the field, the same as the x button beside it. Guarded so an
        // empty field does not swallow Escape from anything else that wants it.
        .onExitCommand { if !searchQuery.isEmpty { searchQuery = "" } }
    }

    // MARK: - Search-path content

    /// Renders one help item for the search path. Each item's id is its index in
    /// the document, which is also how `matches` refers to it.
    @ViewBuilder
    private func searchItem(_ index: Int, _ item: HelpContent) -> some View {
        let id = Self.nodeId(index)
        switch item {
        case .title(let text):
            Text(text).font(.largeTitle).fontWeight(.bold).id(id)
        case .section(let text):
            HelpSection(text, id: id)
        case .intro(let text), .paragraph(let text):
            HelpParagraph(text, id: id)
        case .bullet(let text):
            HelpBullet(text, id: id)
        case .screenshot(let name):
            screenshot(name)
        case .indentedScreenshot(let name):
            screenshot(name, indented: true)
        }
    }

    @ViewBuilder
    private func screenshot(_ name: String, indented: Bool = false) -> some View {
        if let nsImage = NSImage(named: name) {
            Image(nsImage: nsImage)
                .resizable()
                .frame(width: nsImage.size.width / 2, height: nsImage.size.height / 2)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                .padding(.leading, indented ? 16 : 0)
        }
    }

    // MARK: - Search corpus

    private static func nodeId(_ index: Int) -> String { "n-\(index)" }

    /// Searchable text of every item, derived from the same document the view renders.
    private static let searchNodes: [(id: String, text: String)] =
        HelpDocument.content.enumerated().compactMap { index, item in
            item.searchText.map { (nodeId(index), $0) }
        }
}

// MARK: - Layout helpers

struct HelpSection: View {
    let title: String
    let sectionId: String
    @Environment(\.aboutSearchQuery) private var searchQuery
    @Environment(\.aboutActiveNodeId) private var activeNodeId
    @Environment(\.aboutActiveOccurrence) private var activeOccurrence

    init(_ title: String, id sectionId: String) {
        self.title = title
        self.sectionId = sectionId
    }

    var body: some View {
        let titleActive = sectionId == activeNodeId ? activeOccurrence : -1
        Text(highlighted(title, query: searchQuery, activeOccurrence: titleActive))
            .font(.title2)
            .fontWeight(.semibold)
            .padding(.top, 20)
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
