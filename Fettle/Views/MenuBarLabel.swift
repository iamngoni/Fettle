import SwiftUI

struct MenuBarLabel: View {
    var appState: AppState

    var body: some View {
        Group {
            if let symbol = symbol {
                Image(systemName: symbol)
            } else {
                Image("FettleMenuBarIcon")
                    .renderingMode(.template)
            }
        }
            .accessibilityLabel("Fettle")
    }

    private var symbol: String? {
        if appState.cleanMode.isActive { return "lock.fill" }
        if appState.micMute.isActive { return "mic.slash.fill" }
        if appState.presentation.isActive { return "videoprojector.fill" }
        if appState.keepAwake.isActive { return "cup.and.saucer.fill" }
        return nil
    }
}
