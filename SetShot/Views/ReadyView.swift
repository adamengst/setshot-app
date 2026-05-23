import SwiftUI

struct ReadyView: View {
    @Binding var appState: AppState

    var body: some View {
        VStack(spacing: 24) {
            Text("SetShot")
                .font(.largeTitle.bold())
            Text("Snapshot your system settings before and after a macOS update to see exactly what changed.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)
            Button("Take Before Snapshot") {
                // Implemented in SnapshotRunner session
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(48)
    }
}
