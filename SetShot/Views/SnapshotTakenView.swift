import SwiftUI

struct SnapshotTakenView: View {
    let snapshotDate: Date
    @Binding var appState: AppState

    var body: some View {
        VStack(spacing: 24) {
            Text("Before Snapshot Taken")
                .font(.largeTitle.bold())
            Text("Taken \(snapshotDate.formatted(date: .long, time: .shortened))")
                .foregroundStyle(.secondary)
            Text("Update macOS (or make the changes you want to track), then take the after snapshot.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)
            HStack(spacing: 16) {
                Button("Start Over") {
                    appState = .ready
                }
                Button("Take After Snapshot") {
                    // Implemented in SnapshotRunner session
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(48)
    }
}
