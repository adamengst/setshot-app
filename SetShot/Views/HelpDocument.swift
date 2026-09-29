import Foundation

/// One element of the help document, parsed from `documentation.md`.
enum HelpContent {
    case title(String)
    case intro(String)
    case section(String)
    case paragraph(String)
    case bullet(String)
    case screenshot(String)
    case indentedScreenshot(String)

    /// The item's text with markdown syntax removed, for searching.
    var searchText: String? {
        switch self {
        case .title(let t), .intro(let t), .section(let t), .paragraph(let t), .bullet(let t):
            let attr = (try? AttributedString(markdown: t, options: .init(interpretedSyntax: .full))) ?? AttributedString(t)
            return String(attr.characters)
        case .screenshot, .indentedScreenshot:
            return nil
        }
    }
}

/// Loads and parses the bundled `documentation.md`, which is also the source for
/// the website's documentation page. Supports the subset of markdown the file
/// uses: `#` title, `##` sections, paragraphs, `-` bullets, and images
/// (`![alt](images/Name.png)`, indented when they belong to a bullet). Wrapped
/// lines are joined with a space. An image's asset-catalog name is its file name
/// without the extension.
enum HelpDocument {
    static let content: [HelpContent] = {
        guard let url = Bundle.main.url(forResource: "documentation", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return parse(text)
    }()

    static func parse(_ markdown: String) -> [HelpContent] {
        var items: [HelpContent] = []
        var pendingText: [String] = []
        var pendingIsBullet = false
        var seenSection = false

        func flush() {
            guard !pendingText.isEmpty else { return }
            let text = pendingText.joined(separator: " ")
            if pendingIsBullet {
                items.append(.bullet(text))
            } else {
                items.append(seenSection ? .paragraph(text) : .intro(text))
            }
            pendingText = []
            pendingIsBullet = false
        }

        for rawLine in markdown.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flush()
            } else if line.hasPrefix("## ") {
                flush()
                seenSection = true
                items.append(.section(String(line.dropFirst(3))))
            } else if line.hasPrefix("# ") {
                flush()
                items.append(.title(String(line.dropFirst(2))))
            } else if line.hasPrefix("!["), let name = imageName(line) {
                flush()
                items.append(rawLine.hasPrefix(" ") ? .indentedScreenshot(name) : .screenshot(name))
            } else if line.hasPrefix("- ") {
                flush()
                pendingIsBullet = true
                pendingText = [String(line.dropFirst(2))]
            } else {
                pendingText.append(line)
            }
        }
        flush()
        return items
    }

    private static func imageName(_ line: String) -> String? {
        guard let open = line.range(of: "]("), line.hasSuffix(")") else { return nil }
        let path = line[open.upperBound..<line.index(before: line.endIndex)]
        return ((String(path) as NSString).lastPathComponent as NSString).deletingPathExtension
    }
}
