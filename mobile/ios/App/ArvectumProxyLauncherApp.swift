import SwiftUI

@main
struct ArvectumProxyLauncherApp: App {
    @StateObject private var model = AppViewModel()

    init() {
        #if DEBUG
        if AcceptanceRunner.isEnabled {
            Task { @MainActor in
                await AcceptanceRunner.runIfRequested()
            }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
    }
}
