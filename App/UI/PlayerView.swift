import SwiftUI
import EmulationKit

@MainActor
struct PlayerView: View {
    @ObservedObject var session: EmulationSession
    @Environment(\.scenePhase) private var scenePhase
    @State private var confirmingStop = false
    @State private var showingSaveStates = false
    @State private var showingLayout = false
    @State private var editingLandscape = false
    @AppStorage(PlayerConfiguration.portraitKey) private var portraitLayout = ""
    @AppStorage(PlayerConfiguration.landscapeKey) private var landscapeLayout = ""

    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            let config = PlayerConfiguration.decode(landscape ? landscapeLayout : portraitLayout, landscape: landscape)
            VStack(spacing: 8) {
                toolbar(landscape: landscape)
                if let game = session.game {
                    GeometryReader { area in
                        let size = area.size
                        let baseWidth: CGFloat = landscape ? 110 : 140
                        let baseHeight: CGFloat = landscape ? 215 : 250
                        let scale = min(CGFloat(config.controlScale),
                                        max(0.1, (size.height - 12) / baseHeight),
                                        max(0.1, (size.width / 2 - 12) / baseWidth))
                        let groupSize = CGSize(width: baseWidth * scale, height: baseHeight * scale)
                        let bounds = CGRect(origin: .zero, size: size)
                        ZStack {
                            // Keep this display at one identity across layouts and rotations.
                            display(game.system, configuration: config)
                                .padding(.horizontal, landscape && config.showControls ? groupSize.width + 12 : 0)
                                .padding(.bottom, !landscape && config.showControls ? groupSize.height + 16 : 0)
                            if config.showControls {
                                controlGroup(left: true, landscape: landscape, baseSize: CGSize(width: baseWidth, height: baseHeight), scale: scale)
                                    .opacity(config.controlOpacity)
                                    .position(PlayerScreenFrames.controlCenter(config.left, size: groupSize, in: bounds))
                                controlGroup(left: false, landscape: landscape, baseSize: CGSize(width: baseWidth, height: baseHeight), scale: scale)
                                    .opacity(config.controlOpacity)
                                    .position(PlayerScreenFrames.controlCenter(config.right, size: groupSize, in: bounds))
                                systemControls
                                    .frame(width: 126, height: 34)
                                    .scaleEffect(scale)
                                    .frame(width: 126 * scale, height: 34 * scale)
                                    .opacity(config.controlOpacity)
                                    .position(PlayerScreenFrames.controlCenter(config.menu, size: CGSize(width: 126 * scale, height: 34 * scale), in: bounds))
                            }
                        }
                    }
                }
            }.padding(.horizontal, landscape ? 12 : 20).padding(.vertical, 8)
        }
        .background(TandemTheme.background).tint(TandemTheme.mint)
        .interactiveDismissDisabled()
        .sheet(isPresented: $showingSaveStates) { SaveStatesView(session: session) }
        .sheet(isPresented: $showingLayout) {
            PlayerCustomizationView(portrait: $portraitLayout, landscape: $landscapeLayout, initialLandscape: editingLandscape)
        }
        .confirmationDialog("End this session?", isPresented: $confirmingStop, titleVisibility: .visible) {
            Button("Stop Emulation", role: .destructive) { Task { await session.stop() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("In-game saves are managed by the emulation core.") }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { Task { await session.setPaused(true) } }
        }
        .onChange(of: session.state) { _, state in
            if state == .running, scenePhase != .active {
                Task { await session.setPaused(true) }
            }
        }
    }

    private func toolbar(landscape: Bool) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(session.game?.title ?? "Tandem").font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(session.coreName).font(.system(size: 10, design: .monospaced)).foregroundStyle(TandemTheme.muted)
            }
            Spacer()
            Button("Player layout", systemImage: "rectangle.3.group") {
                Task {
                    await session.setPaused(true)
                    guard session.canPause else { return }
                    editingLandscape = landscape
                    showingLayout = true
                }
            }.labelStyle(.iconOnly).frame(width: 36, height: 44)
                .disabled(!session.canPause || session.isStateBusy)
            if session.supportsSaveStates {
                Button("Save states", systemImage: "tray.full") { showingSaveStates = true }
                    .labelStyle(.iconOnly).frame(width: 36, height: 44).disabled(!session.canPause || session.isStateBusy)
            }
            Button {
                Task { await session.setPaused(!isPaused) }
            } label: {
                Image(systemName: isPaused ? "play.fill" : "pause.fill").frame(width: 36, height: 36)
            }.disabled(!session.canPause).accessibilityLabel(isPaused ? "Resume" : "Pause")
            Button { confirmingStop = true } label: {
                Image(systemName: "xmark").frame(width: 36, height: 36)
            }.accessibilityLabel("End session")
        }.frame(minHeight: 44)
    }

    private var isPaused: Bool {
        if case .paused = session.state { return true }
        return false
    }

    private func controlGroup(left: Bool, landscape: Bool, baseSize: CGSize, scale: CGFloat) -> some View {
        ControllerSide(session: session, left: left, compact: landscape)
            .frame(width: baseSize.width, height: baseSize.height)
            .scaleEffect(scale)
            .frame(width: baseSize.width * scale, height: baseSize.height * scale)
    }

    private func display(_ system: GameSystem, configuration: PlayerConfiguration) -> some View {
        ZStack {
            MetalDisplay(session: session, system: system, configuration: configuration)
            switch session.state {
            case .starting:
                VStack(spacing: 12) {
                    ProgressView().tint(TandemTheme.mint)
                    Text("Starting emulation…").font(.footnote)
                }.padding(24).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            case .paused:
                Button { Task { await session.setPaused(false) } } label: {
                    Label("Resume", systemImage: "play.fill").font(.headline).padding(20)
                }.background(.ultraThinMaterial, in: Capsule())
            case .failed(let message):
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle").font(.title2).foregroundStyle(TandemTheme.mint)
                    Text("Unable to start").font(.headline)
                    Text(message).font(.footnote).multilineTextAlignment(.center).foregroundStyle(TandemTheme.muted)
                    Button("Back to Library") { Task { await session.stop() } }.buttonStyle(.bordered)
                }.padding(24).frame(maxWidth: 380).background(TandemTheme.surface, in: RoundedRectangle(cornerRadius: 16))
            case .stopping:
                ProgressView("Ending session…").padding(20).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            default: EmptyView()
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var systemControls: some View {
        HStack(spacing: 8) {
            HoldButton(title: "−") { session.setButton(.minus, pressed: $0) }.frame(width: 34, height: 28)
            HoldButton(title: "⌂") { session.setButton(.home, pressed: $0) }.frame(width: 34, height: 28)
            HoldButton(title: "+") { session.setButton(.plus, pressed: $0) }.frame(width: 34, height: 28)
        }
    }
}
