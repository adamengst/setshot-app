import SwiftUI

@main
struct SetShotApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
                .task { await appModel.loadKB() }
        }
        .windowResizability(.contentSize)
    }
}
