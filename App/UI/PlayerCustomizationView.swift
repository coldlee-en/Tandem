import SwiftUI

@MainActor
struct PlayerCustomizationView: View {
    @Binding var portrait: String
    @Binding var landscape: String
    @Environment(\.dismiss) private var dismiss
    @State private var editingLandscape: Bool

    init(portrait: Binding<String>, landscape: Binding<String>, initialLandscape: Bool) {
        _portrait = portrait
        _landscape = landscape
        _editingLandscape = State(initialValue: initialLandscape)
    }

    private var configuration: Binding<PlayerConfiguration> {
        Binding {
            PlayerConfiguration.decode(editingLandscape ? landscape : portrait, landscape: editingLandscape)
        } set: { value in
            if editingLandscape { landscape = value.serialized }
            else { portrait = value.serialized }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Orientation", selection: $editingLandscape) {
                        Text("Portrait").tag(false)
                        Text("Landscape").tag(true)
                    }.pickerStyle(.segmented)
                    Text("Each orientation has its own settings. Changes save automatically. The game stays paused until you resume.")
                        .font(.footnote).foregroundStyle(TandemTheme.muted)
                }
                Section("Layout preview") {
                    PlayerLayoutPreview(configuration: configuration)
                        .frame(height: 210)
                    Text("Drag the L, R, and Menu handles to place control groups, or use the position sliders below.")
                        .font(.caption).foregroundStyle(TandemTheme.muted)
                }
                Section("Screens") {
                    Picker("Arrangement", selection: configuration.layout) {
                        ForEach(PlayerScreenLayout.allCases) { layout in
                            Text(layout.label).tag(layout)
                        }
                    }
                    adjustment("Screen size", value: configuration.screenScale, range: 0.65...1)
                    VStack(alignment: .leading) {
                        Text("Screen gap: \(Int(configuration.wrappedValue.screenGap)) pt")
                        Slider(value: configuration.screenGap, in: 0...32, step: 1)
                            .accessibilityLabel("Screen gap")
                    }
                }
                Section("Touch controls") {
                    Toggle("Show touch controls", isOn: configuration.showControls)
                    adjustment("Control size", value: configuration.controlScale, range: 0.75...1.15)
                    adjustment("Opacity", value: configuration.controlOpacity, range: 0.25...1)
                    Text("Hide controls when using a controller. The layout button stays available in the player toolbar.")
                        .font(.caption).foregroundStyle(TandemTheme.muted)
                }
                Section("Left controls") { position(configuration.left) }
                Section("Right controls") { position(configuration.right) }
                Section("Menu controls") { position(configuration.menu) }
                Section {
                    Button("Reset this orientation") {
                        configuration.wrappedValue = .defaults(landscape: editingLandscape)
                    }
                }
            }
            .scrollContentBackground(.hidden).background(TandemTheme.background)
            .navigationTitle("Player layout").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
        }.tint(TandemTheme.mint)
    }

    private func adjustment(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading) {
            Text("\(title): \(Int(value.wrappedValue * 100))%")
            Slider(value: value, in: range, step: 0.01).accessibilityLabel(title)
        }
    }

    private func position(_ anchor: Binding<ControlAnchor>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            adjustment("Horizontal position", value: anchor.x, range: 0...1)
            adjustment("Vertical position", value: anchor.y, range: 0...1)
        }
    }
}

private struct PlayerLayoutPreview: View {
    @Binding var configuration: PlayerConfiguration

    var body: some View {
        GeometryReader { geometry in
            let bounds = CGRect(origin: .zero, size: geometry.size)
            let frames = PlayerScreenFrames.calculate(in: bounds.insetBy(dx: 12, dy: 12), configuration: configuration)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.7))
                screen("Top", frame: frames.primary)
                screen("Touch", frame: frames.secondary)
                if configuration.showControls {
                    handle("L", anchor: $configuration.left, bounds: bounds)
                    handle("R", anchor: $configuration.right, bounds: bounds)
                    handle("Menu", anchor: $configuration.menu, bounds: bounds)
                }
            }.coordinateSpace(name: "layout-preview")
        }.accessibilityElement(children: .ignore)
            .accessibilityLabel("Screen and control layout preview. Position sliders are available below.")
    }

    private func screen(_ title: String, frame: CGRect) -> some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(TandemTheme.mint.opacity(0.15))
            .overlay(Text(title).font(.caption).foregroundStyle(.white))
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
    }

    private func handle(_ title: String, anchor: Binding<ControlAnchor>, bounds: CGRect) -> some View {
        let size = CGSize(width: 52 * configuration.controlScale, height: 34 * configuration.controlScale)
        let center = PlayerScreenFrames.controlCenter(anchor.wrappedValue, size: size, in: bounds)
        return Text(title).font(.caption.bold())
            .frame(width: size.width, height: size.height)
            .background(TandemTheme.mint, in: Capsule())
            .foregroundStyle(Color.black)
            .opacity(configuration.controlOpacity)
            .position(center)
            .gesture(DragGesture(coordinateSpace: .named("layout-preview")).onChanged { value in
                anchor.wrappedValue = ControlAnchor(
                    x: min(1, max(0, Double(value.location.x / max(1, bounds.width)))),
                    y: min(1, max(0, Double(value.location.y / max(1, bounds.height)))))
            })
    }
}
