import SwiftUI

/// A compact menu that lists audio devices for the given scope and switches the
/// system default when one is chosen.
struct DevicePicker: View {
    var input: Bool
    var onChange: () -> Void = {}
    @State private var devices: [AudioDevice] = []

    var body: some View {
        Menu {
            ForEach(devices) { device in
                Button(device.name) {
                    AudioSystem.setDefaultDevice(device.id, input: input)
                    onChange()
                }
            }
        } label: {
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(hex: 0x8E8E96))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onAppear { devices = AudioSystem.devices(input: input) }
    }
}
