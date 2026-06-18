import SwiftUI
import AppKit

// MARK: - Data model

private struct RNSection: Identifiable {
    let id = UUID()
    let version: String
    let bullets: [String]
}

// MARK: - Markdown parser

private func loadReleaseNotes() -> [RNSection] {
    guard let url = Bundle.main.url(forResource: "ReleaseNotes", withExtension: "md"),
          let text = try? String(contentsOf: url, encoding: .utf8)
    else { return [] }

    var sections: [RNSection] = []
    var currentVersion: String?
    var currentBullets: [String] = []

    for line in text.components(separatedBy: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("## ") {
            if let v = currentVersion {
                sections.append(RNSection(version: v, bullets: currentBullets))
            }
            currentVersion = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            currentBullets = []
        } else if trimmed.hasPrefix("- ") {
            currentBullets.append(String(trimmed.dropFirst(2)))
        }
    }
    if let v = currentVersion {
        sections.append(RNSection(version: v, bullets: currentBullets))
    }
    return sections
}

// MARK: - Highlight helper

private func rnHighlighted(_ text: String, query: String, activeOccurrence: Int = -1) -> AttributedString {
    var attr: AttributedString
    do {
        attr = try AttributedString(markdown: text, options: .init(interpretedSyntax: .full))
    } catch {
        attr = AttributedString(text)
    }
    guard !query.isEmpty else { return attr }
    let plain = String(attr.characters)
    let chars = attr.characters
    var pos = plain.startIndex
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

// MARK: - NSTextView renderer (non-search path)

private struct ReleaseNotesNSTextView: NSViewRepresentable {
    let sections: [RNSection]

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        guard let tv = scroll.documentView as? NSTextView else { return scroll }
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 40, height: 40)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        tv.textStorage?.setAttributedString(buildAttributedString())
    }

    private func buildAttributedString() -> NSAttributedString {
        let result = NSMutableAttributedString()
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)

        func appendMarkdown(_ markdown: String, font: NSFont, color: NSColor, paragraph: NSParagraphStyle) {
            let attr = (try? AttributedString(markdown: markdown, options: opts)) ?? AttributedString(markdown)
            for run in attr.runs {
                let chars = String(attr[run.range].characters)
                let intent = run.inlinePresentationIntent
                let isBold = intent?.contains(.stronglyEmphasized) == true
                let f: NSFont = isBold ? .systemFont(ofSize: font.pointSize, weight: .bold) : font
                result.append(NSAttributedString(string: chars, attributes: [
                    .font: f, .foregroundColor: color, .paragraphStyle: paragraph,
                ]))
            }
        }

        func ps(spacingBefore: CGFloat, spacingAfter: CGFloat, bulletIndent: Bool = false) -> NSParagraphStyle {
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

        for section in sections {
            if result.length > 0 { result.append(NSAttributedString(string: "\n")) }
            appendMarkdown(section.version,
                           font: .systemFont(ofSize: 22, weight: .semibold),
                           color: .labelColor,
                           paragraph: ps(spacingBefore: 24, spacingAfter: 10))
            for bullet in section.bullets {
                result.append(NSAttributedString(string: "\n"))
                appendMarkdown("\u{2022}\t" + bullet,
                               font: .systemFont(ofSize: 14),
                               color: .labelColor,
                               paragraph: ps(spacingBefore: 0, spacingAfter: 6, bulletIndent: true))
            }
        }
        return result
    }
}

// MARK: - Main view

struct ReleaseNotesView: View {
    @State private var searchQuery = ""
    @State private var matchIndex = 0

    private static let sections: [RNSection] = loadReleaseNotes()

    private static let searchNodes: [(id: String, text: String)] = {
        var nodes: [(id: String, text: String)] = []
        for section in sections {
            nodes.append(("rn-\(section.version)-title", section.version))
            for (i, bullet) in section.bullets.enumerated() {
                let plain: String
                if let attr = try? AttributedString(markdown: bullet, options: .init(interpretedSyntax: .full)) {
                    plain = String(attr.characters)
                } else {
                    plain = bullet
                }
                nodes.append(("rn-\(section.version)-b\(i)", plain))
            }
        }
        return nodes
    }()

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
                ReleaseNotesNSTextView(sections: Self.sections)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 28) {
                            ForEach(Self.sections) { section in
                                sectionBlock(section)
                            }
                        }
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

    // MARK: - Search path views

    private func sectionBlock(_ section: RNSection) -> some View {
        let titleId = "rn-\(section.version)-title"
        let isTitleActive = titleId == activeNodeId
        let titleOcc = isTitleActive ? activeOccurrenceIndex : -1
        return VStack(alignment: .leading, spacing: 8) {
            Text(rnHighlighted(section.version, query: searchQuery, activeOccurrence: titleOcc))
                .font(.title2).fontWeight(.semibold)
                .id(titleId)
            ForEach(Array(section.bullets.enumerated()), id: \.offset) { i, bullet in
                bulletRow(bullet, nodeId: "rn-\(section.version)-b\(i)")
            }
        }
    }

    private func bulletRow(_ bullet: String, nodeId: String) -> some View {
        let isActive = nodeId == activeNodeId
        let occ = isActive ? activeOccurrenceIndex : -1
        return HStack(alignment: .top, spacing: 6) {
            Text("\u{2022}").foregroundStyle(.secondary)
            Text(rnHighlighted(bullet, query: searchQuery, activeOccurrence: occ))
                .fixedSize(horizontal: false, vertical: true)
        }
        .id(nodeId)
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search release notes", text: $searchQuery)
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
}
