import SwiftUI

struct MenuBarLabel: View {
    var appState: AppState

    var body: some View {
        // One neutral, monochrome Fettle mark — it never morphs into
        // tool-specific metaphors (no coffee cup, no pill, no lock) so Fettle
        // never visually apes Lungo, Caffeine, Amphetamine, etc. Tool state is
        // shown inside the panel, not by impersonating another app's icon.
        Image("FettleMenuBarIcon")
            .renderingMode(.template)
            .accessibilityLabel("Fettle")
    }
}
