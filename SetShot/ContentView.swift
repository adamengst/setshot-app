import SwiftUI

enum AppState {
    case library
    case results(DiffResult, before: StoredSnapshot, after: StoredSnapshot)
}

struct ContentView: View {
    @EnvironmentObject var appModel: AppModel
    @State private var appState: AppState = .library

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch appState {
                case .library:
                    SnapshotLibraryView(appState: $appState)
                case .results(let diff, let before, let after):
                    ResultsView(diff: diff, before: before, after: after, appState: $appState)
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
        .frame(minWidth: 680, minHeight: 420)
    }
}
