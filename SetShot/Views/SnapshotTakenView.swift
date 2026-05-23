import SwiftUI

struct SnapshotTakenView: View {
    let snapshotDate: Date
    @EnvironmentObject var appModel: AppModel
    @Binding var appState: AppState
    @State private var isRunning = false
    @State private var errorMessage: String?

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

            if isRunning {
                ProgressView("Capturing settings…")
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 280)
            } else {
                HStack(spacing: 16) {
                    Button("Start Over") {
                        appState = .ready
                    }
                    Button("Take After Snapshot") {
                        takeAfterSnapshot()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
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

    private func takeAfterSnapshot() {
        guard let before = appModel.beforeSnapshot else { return }
        isRunning = true
        Task {
            do {
                let after = try await SnapshotRunner().run()
                let diff = try await DiffEngine().diff(before: before, after: after, kb: appModel.kb)
                appState = .results(diff)
            } catch {
                errorMessage = error.localizedDescription
                isRunning = false
            }
        }
    }
}
