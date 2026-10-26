import SwiftUI
import UniformTypeIdentifiers
import EmulationKit

@MainActor
struct SettingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var importMode: SystemImportMode = .keys
    @State private var showingImporter = false

    private enum SystemImportMode { case keys, firmware, threeDSKeys, threeDSSeeds }
    var body: some View {
        NavigationStack {
            List {
                Section("Emulation cores") {
                    ForEach(GameSystem.allCases) { system in
                        let availability = CoreRegistry.availability(for: system)
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(system.displayName).font(.headline)
                                Spacer()
                                Image(systemName: availability.isAvailable ? "checkmark.circle.fill" : "wrench.and.screwdriver")
                                    .foregroundStyle(availability.isAvailable ? TandemTheme.mint : TandemTheme.muted)
                            }
                            Text(availability.summary).font(.subheadline).foregroundStyle(TandemTheme.mint)
                            Text(availability.detail).font(.footnote).foregroundStyle(TandemTheme.muted)
                        }.padding(.vertical, 8)
                    }
                }
                Section("Game files") {
                    ForEach(GameSystem.allCases) { system in
                        LabeledContent(system == .nintendo3DS ? "3DS" : "Switch") {
                            Text(system.supportedExtensions.map { "." + $0 }.joined(separator: ", "))
                                .font(.caption.monospaced()).multilineTextAlignment(.trailing)
                        }
                    }
                    Text("Imports are copied into Tandem’s local library. Removing a game removes that copy.")
                        .font(.footnote).foregroundStyle(TandemTheme.muted)
                }
                Section("System files") {
                    Button {
                        importMode = .threeDSKeys
                        showingImporter = true
                    } label: {
                        Label("Import 3DS AES keys", systemImage: "key")
                    }
                    .disabled(model.isManagingSystemData || model.session.game != nil)
                    Button {
                        importMode = .threeDSSeeds
                        showingImporter = true
                    } label: {
                        Label("Import 3DS seed database", systemImage: "internaldrive")
                    }
                    .disabled(model.isManagingSystemData || model.session.game != nil)
                    Button {
                        importMode = .keys
                        showingImporter = true
                    } label: {
                        Label("Import Switch keys", systemImage: "key")
                    }
                    .disabled(model.isManagingSystemData || model.session.game != nil)
                    Button {
                        importMode = .firmware
                        showingImporter = true
                    } label: {
                        Label("Install Switch firmware", systemImage: "shippingbox")
                    }
                    .disabled(model.isManagingSystemData || model.session.game != nil || !SwitchCore.isBundled)
                    if model.isManagingSystemData {
                        ProgressView("Preparing system data…")
                            .tint(TandemTheme.mint)
                    }
                    if let message = model.systemDataMessage {
                        Text(message).font(.footnote).foregroundStyle(TandemTheme.mint)
                    }
                    Text("Core data, firmware, and keys stay on this device. Consult the build guide for each core’s setup.")
                        .font(.footnote).foregroundStyle(TandemTheme.muted)
                    Text(model.systemDirectory.path).font(.caption.monospaced()).textSelection(.enabled)
                }
                Section("Controls") {
                    Label("Touch controls and analog sticks", systemImage: "hand.draw")
                    Label("Compatible Bluetooth controllers", systemImage: "gamecontroller")
                    Text("Tandem pauses when you leave the player or the app becomes inactive.")
                        .font(.footnote).foregroundStyle(TandemTheme.muted)
                }
                Section {
                    HStack {
                        Text("Tandem").font(.headline)
                        Spacer()
                        Text("Development build").font(.caption).foregroundStyle(TandemTheme.muted)
                    }
                }
            }
            .scrollContentBackground(.hidden).background(TandemTheme.background)
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }.tint(TandemTheme.mint).preferredColorScheme(.dark)
        .fileImporter(isPresented: $showingImporter,
                      allowedContentTypes: importMode == .firmware ? [.zip] : [.data],
                      allowsMultipleSelection: false) { [mode = importMode] result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                switch mode {
                case .keys: model.importSwitchKeys(url)
                case .firmware: model.installSwitchFirmware(url)
                case .threeDSKeys: model.importThreeDSData(url, seedDatabase: false)
                case .threeDSSeeds: model.importThreeDSData(url, seedDatabase: true)
                }
            case .failure(let error): model.errorMessage = error.localizedDescription
            }
        }
        .alert("Tandem", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
}
