import SwiftUI

enum AppState {
    case ready
    case snapshotTaken(at: Date)
    case results(DiffResult)
}

struct ContentView: View {
    @State private var appState: AppState = .ready

    var body: some View {
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
        .frame(minWidth: 560, minHeight: 340)
    }
}
