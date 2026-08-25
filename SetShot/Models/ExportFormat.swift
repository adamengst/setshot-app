import UniformTypeIdentifiers

enum ExportFormat {
    case html
    case markdown

    var fileExtension: String {
        switch self {
        case .html: return "html"
        case .markdown: return "md"
        }
    }

    var contentType: UTType {
        switch self {
        case .html: return .html
        // Not every system declares a Markdown type, and a save panel with no valid
        // type will not let the file be written.
        case .markdown: return UTType(filenameExtension: "md") ?? .plainText
        }
    }
}
