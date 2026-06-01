import SwiftUI

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
                Text("Version \(appVersion) (build \(build))")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
            .padding(.top, 24)
            .padding(.bottom, 16)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Designed by Adam Engst")
                Text("Programmed by Claude Code")
                Text("Icon by ChatGPT Images")
                Text("Published by TidBITS Publishing")
                Text("Copyright © 2025–2026 TidBITS Publishing Inc.")
                Text("Released under the MIT License")
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
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
                Text("\(kbVersion)\(kbDate)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
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
        .frame(width: 325)
    }
}
