import SwiftUI
import AppKit

struct SettingsPaneIcon: View {
    let settingsURL: String?
    let domain: String
    var iconBundleID: String? = nil
    var size: CGFloat = 28

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .task(id: (settingsURL ?? domain) + (iconBundleID ?? "")) {
            image = await SettingsPaneIconProvider.shared.icon(
                forSettingsURL: settingsURL,
                domain: domain,
                iconBundleID: iconBundleID
            )
        }
    }
}
