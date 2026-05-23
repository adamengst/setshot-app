import SwiftUI

struct ReadyView: View {
    @EnvironmentObject var appModel: AppModel
    @Binding var appState: AppState
    @State private var isRunning = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Text("SetShot")
                .font(.largeTitle.bold())
            Text("Snapshot your system settings before and after a macOS update to see exactly what changed.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)

            if isRunning {
                ProgressView("Capturing settings…")
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 280)
            } else {
                Button("Take Before Snapshot") {
                    takeSnapshot()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(48)
        .alert("Snapshot Failed", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func takeSnapshot() {
        isRunning = true
        Task {
            do {
                let snapshot = try await SnapshotRunner().run()
                appModel.beforeSnapshot = snapshot
                appState = .snapshotTaken(at: snapshot.takenAt)
            } catch {
                errorMessage = error.localizedDescription
            }
            isRunning = false
        }
    }
}
