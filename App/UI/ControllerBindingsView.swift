import SwiftUI
import EmulationKit

struct ControllerBindingsView: View {
    @AppStorage(ControllerBindings.storageKey) private var storedBindings = ""
    @AppStorage(ControllerBindings.swapSticksKey) private var swapSticks = false

    var body: some View {
        List {
            Section {
                Toggle("Swap analog sticks", isOn: $swapSticks)
                Text("Button positions use the Xbox and PlayStation layout. Some controllers do not provide every button to iOS.")
                    .font(.footnote).foregroundStyle(TandemTheme.muted)
            }
            Section {
                ForEach(ControllerControl.allCases) { control in
                    Picker(control.label, selection: binding(for: control)) {
                        ForEach(GameButton.allCases) { button in
                            Text(button.label).tag(button)
                        }
                    }
                }
            } header: {
                Text("Button bindings")
            } footer: {
                Text("Choosing a button already in use swaps the two assignments. These settings apply to both systems and take effect the next time you start a game.")
            }
            Section {
                Button("Reset controller bindings") {
                    storedBindings = ""
                    swapSticks = false
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(TandemTheme.background)
        .navigationTitle("Controller bindings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func binding(for control: ControllerControl) -> Binding<GameButton> {
        Binding {
            ControllerBindings(serialized: storedBindings)[control]
        } set: { button in
            var bindings = ControllerBindings(serialized: storedBindings)
            bindings.assign(button, to: control)
            storedBindings = bindings.serialized
        }
    }
}
