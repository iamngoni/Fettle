import SwiftUI

@main
struct FettleApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            RootView()
                .environment(appState)
                .frame(width: Theme.panelWidth)
        } label: {
            MenuBarLabel(appState: appState)
        }
        .menuBarExtraStyle(.window)
    }
}
