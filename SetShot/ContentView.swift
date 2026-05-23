import SwiftUI

enum AppState {
    case ready
    case snapshotTaken(at: Date)
    case results(DiffResult)
}

struct ContentView: View {
    @EnvironmentObject var appModel: AppModel
    @State private var appState: AppState = .ready

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch appState {
                case .ready:
                    ReadyView(appState: $appState)
                case .snapshotTaken(let date):
                    SnapshotTakenView(snapshotDate: date, appState: $appState)
                case .results(let diff):
                    ResultsView(diff: diff, appState: $appState)
                }
            }

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
        .frame(minWidth: 560, minHeight: 340)
    }
}
