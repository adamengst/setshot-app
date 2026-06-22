import SwiftUI
import AppKit

/// Renders multiple plain-text lines in a single NSTextView so the whole block
/// can be selected and copied as one unit. Plain `.textSelection(.enabled)`
/// does not work on macOS Tahoe (26).
private struct SelectableCreditsText: NSViewRepresentable {
    let lines: [String]
    let fontSize: CGFloat
    let color: NSColor
    let lineSpacing: CGFloat
    var alignment: NSTextAlignment = .left

    private func buildAttributedString() -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        paragraph.alignment = alignment
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        return NSAttributedString(string: lines.joined(separator: "\n"), attributes: attrs)
    }

    func makeNSView(context: Context) -> NSTextView {
        let tv = NSTextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainerInset = .zero
        tv.isHorizontallyResizable = false
        tv.isVerticallyResizable = true
        tv.textContainer?.widthTracksTextView = true
        return tv
    }

    func updateNSView(_ tv: NSTextView, context: Context) {
        tv.textStorage?.setAttributedString(buildAttributedString())
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView tv: NSTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0, width < 1e9 else { return nil }
        tv.textContainer?.size = CGSize(width: width, height: .greatestFiniteMagnitude)
        tv.layoutManager?.ensureLayout(for: tv.textContainer!)
        let h = tv.layoutManager?.usedRect(for: tv.textContainer!).height ?? (fontSize * 1.5)
        return CGSize(width: width, height: ceil(h))
    }
}

struct AboutPanelView: View {
    @EnvironmentObject var appModel: AppModel
    @State private var isRefreshing = false

    private let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    private let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                if let icon = NSApp.applicationIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 80, height: 80)
                }
                Text("SetShot")
                    .font(.title.bold())
                SelectableCreditsText(
                    lines: ["Version \(appVersion) (build \(build))"],
                    fontSize: 11,
                    color: .secondaryLabelColor,
                    lineSpacing: 0,
                    alignment: .center
                )
            }
            .padding(.top, 24)
            .padding(.bottom, 16)

            Divider()

            SelectableCreditsText(
                lines: [
                    "Designed by Adam Engst",
                    "Programmed by Claude Code",
                    "Icon by ChatGPT Images",
                    "Published by TidBITS Publishing",
                    "Copyright © 2025–2026 TidBITS Publishing Inc.",
                    "Released under the MIT License"
                ],
                fontSize: 12,
                color: .secondaryLabelColor,
                lineSpacing: 4
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)

            Divider()

            HStack {
                let kbVersion = appModel.kb.version > 0 ? "Knowledge Base v\(appModel.kb.version)" : "Knowledge Base"
                let kbDate: String = {
                    guard let date = appModel.kb.updatedAt else { return "" }
                    return " · " + date.formatted(.dateTime.month(.abbreviated).day().year())
                }()
                SelectableCreditsText(
                    lines: ["\(kbVersion)\(kbDate)"],
                    fontSize: 12,
                    color: .secondaryLabelColor,
                    lineSpacing: 0
                )
                Spacer()
                if isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Refresh") {
                        isRefreshing = true
                        Task {
                            await appModel.refreshKB()
                            isRefreshing = false
                        }
                    }
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .frame(width: 380)
    }
}
