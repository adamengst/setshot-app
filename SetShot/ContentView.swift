import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appModel: AppModel

    var body: some View {
        VStack(spacing: 0) {
            SnapshotLibraryView()

            if appModel.kbUnavailable {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                    Text("Knowledge base unavailable — no network and no local cache. Changes will appear without descriptions.")
                        .font(.caption)
                }
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(Color.yellow.opacity(0.15))
            }
        }
        .frame(minWidth: 680, minHeight: 420)
    }
}
