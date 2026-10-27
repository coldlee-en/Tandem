import SwiftUI
import EmulationKit

@MainActor
struct PlayerView: View {
    @ObservedObject var session: EmulationSession
    @Environment(\.scenePhase) private var scenePhase
    @State private var confirmingStop = false

    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            VStack(spacing: landscape ? 6 : 16) {
                toolbar
                if let game = session.game {
                    // Keep the MetalDisplay at one structural identity through
                    // rotations so a running core never loses its native layers.
                    ZStack {
                        display(game.system)
                            .padding(.horizontal, landscape ? 117 : 0)
                            .padding(.bottom, landscape ? 0 : 255)
                        HStack {
                            ControllerSide(session: session, left: true, compact: landscape)
                                .frame(width: landscape ? 105 : 130)
                            Spacer(minLength: 4)
                            ControllerSide(session: session, left: false, compact: landscape)
                                .frame(width: landscape ? 105 : 130)
                        }
                        .frame(height: landscape ? nil : 245)
                        .frame(maxHeight: .infinity, alignment: landscape ? .center : .bottom)
                        if !landscape {
                            systemControls
                                .frame(maxHeight: .infinity, alignment: .bottom)
                                .padding(.bottom, 105)
                        }
                    }
                    if landscape { systemControls }
                }
            }.padding(.horizontal, landscape ? 12 : 20).padding(.vertical, 8)
        }
        .background(TandemTheme.background).tint(TandemTheme.mint)
        .interactiveDismissDisabled()
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

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(session.game?.title ?? "Tandem").font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(session.coreName).font(.system(size: 10, design: .monospaced)).foregroundStyle(TandemTheme.muted)
            }
            Spacer()
            Button {
                Task { await session.setPaused(!isPaused) }
            } label: {
                Image(systemName: isPaused ? "play.fill" : "pause.fill").frame(width: 36, height: 36)
            }.disabled(!session.canPause).accessibilityLabel(isPaused ? "Resume" : "Pause")
            Button { confirmingStop = true } label: {
                Image(systemName: "xmark").frame(width: 36, height: 36)
            }.accessibilityLabel("End session")
        }.frame(height: 42)
    }

    private var isPaused: Bool {
        if case .paused = session.state { return true }
        return false
    }

    private func display(_ system: GameSystem) -> some View {
        ZStack {
            MetalDisplay(session: session, system: system)
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
