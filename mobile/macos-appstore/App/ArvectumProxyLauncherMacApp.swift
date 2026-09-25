import SwiftUI

@main
struct ArvectumProxyLauncherMacApp: App {
    @StateObject private var model = AppViewModel()
    @AppStorage("privacyDisclosureAccepted.v1") private var privacyDisclosureAccepted = false
    @State private var helpPresented = false

    var body: some Scene {
        WindowGroup {
            Group {
                if privacyDisclosureAccepted {
                    ContentView()
                } else {
                    PrivacyDisclosureView {
                        privacyDisclosureAccepted = true
                    }
                }
            }
            .environmentObject(model)
            .sheet(isPresented: $helpPresented) {
                APLHelpView {
                    helpPresented = false
                }
            }
        }
        .commands {
            CommandGroup(replacing: .help) {
                Button("Справка Arvectum Proxy Launcher") {
                    helpPresented = true
                }
            }
        }
    }
}
