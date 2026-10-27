import SwiftUI
import UIKit
import UniformTypeIdentifiers
import EmulationKit

@MainActor
struct LibraryView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var session: EmulationSession
    @State private var search = ""
    @State private var selectedSystem: GameSystem?
    @State private var importing = false
    @State private var showingSettings = false
    @State private var coverTarget: GameRecord?
    @State private var importingCover = false
    @State private var favoritesOnly = false
    @AppStorage("favoriteGames") private var storedFavorites = ""

    private var favoriteIDs: Set<String> {
        Set(storedFavorites.split(separator: ",").map(String.init))
    }

    private func toggleFavorite(_ game: GameRecord) {
        var ids = favoriteIDs
        let id = game.id.uuidString
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        storedFavorites = ids.sorted().joined(separator: ",")
    }

    init(model: AppModel) {
        self.model = model
        self.session = model.session
    }

    private var filteredGames: [GameRecord] {
        model.games.filter { game in
            (!favoritesOnly || favoriteIDs.contains(game.id.uuidString))
                && (selectedSystem == nil || game.system == selectedSystem)
                && (search.isEmpty || game.title.localizedCaseInsensitiveContains(search))
        }.sorted { ($0.lastPlayedAt ?? $0.importedAt) > ($1.lastPlayedAt ?? $1.importedAt) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    introduction
                    if search.isEmpty, !favoritesOnly,
                       let recent = model.games.filter({ $0.lastPlayedAt != nil }).max(by: { ($0.lastPlayedAt ?? .distantPast) < ($1.lastPlayedAt ?? .distantPast) }) {
                        continuePlaying(recent)
                    }
                    systemPicker
                    if model.isImporting {
                        HStack(spacing: 12) {
                            ProgressView().tint(TandemTheme.mint)
                            Text("Importing into your library…").font(.subheadline)
                        }.padding().frame(maxWidth: .infinity, alignment: .leading)
                            .background(TandemTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                    }
                    if filteredGames.isEmpty { emptyLibrary }
                    else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 155, maximum: 240), spacing: 16)], spacing: 20) {
                            ForEach(filteredGames) { game in
                                GameCard(game: game, coverURL: model.coverURL(for: game), coverVersion: model.coverVersions[game.id, default: 0]) { model.launch(game) }
                                    .contextMenu {
                                        Button("Play", systemImage: "play.fill") { model.launch(game) }
                                        Button(favoriteIDs.contains(game.id.uuidString) ? "Remove from Favorites" : "Add to Favorites", systemImage: favoriteIDs.contains(game.id.uuidString) ? "heart.slash" : "heart") { toggleFavorite(game) }
                                        Button("Choose Cover Image", systemImage: "photo") { coverTarget = game; importingCover = true }
                                        Button("Remove Cover Image", systemImage: "photo.badge.minus") { model.removeCover(for: game) }
                                        Button("Remove from Library", systemImage: "trash", role: .destructive) { model.remove(game) }
                                    }
                            }
                        }
                    }
                }.padding(24).frame(maxWidth: 1000)
                    .frame(maxWidth: .infinity)
            }
            .background(TandemTheme.background)
            .navigationTitle("Tandem")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "slider.horizontal.3") { showingSettings = true }
                    Button("Import Games", systemImage: "plus") { importing = true }.disabled(model.isImporting)
                }
            }
            .searchable(text: $search, prompt: "Search your library")
        }
        .tint(TandemTheme.mint)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): model.importGames(urls)
            case .failure(let error): model.errorMessage = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $importingCover, allowedContentTypes: [.image], allowsMultipleSelection: false) { result in
            defer { coverTarget = nil }
            switch result {
            case .success(let urls): if let url = urls.first, let game = coverTarget { model.importCover(url, for: game) }
            case .failure(let error): model.errorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $showingSettings) { SettingsView(model: model) }
        .alert("Tandem", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .fullScreenCover(isPresented: Binding(get: { session.game != nil }, set: { shown in
            if !shown { Task { await session.stop() } }
        })) { PlayerView(session: session) }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(TandemTheme.mint).frame(width: 6, height: 6)
                Text("YOUR GAMES. TOGETHER.").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2)
            }.foregroundStyle(TandemTheme.muted)
            Text("Your games.\nYour next adventure.")
                .font(.system(size: 34, weight: .semibold, design: .serif)).tracking(-1)
            Text("A home for your handheld collection")
                .font(.subheadline).foregroundStyle(TandemTheme.muted)
        }.padding(.top, 6)
    }

    private var systemPicker: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Your library").font(.title3.weight(.semibold))
                Spacer()
                Button { favoritesOnly.toggle() } label: {
                    Label(favoritesOnly ? "Favorites" : "All games", systemImage: favoritesOnly ? "heart.fill" : "heart")
                }.buttonStyle(.bordered).accessibilityHint("Filter your library to favorite games")
            }
            Picker("System", selection: $selectedSystem) {
                Text("All games").tag(Optional<GameSystem>.none)
                Text("3DS").tag(Optional<GameSystem>.some(.nintendo3DS))
                Text("Switch").tag(Optional<GameSystem>.some(.nintendoSwitch))
            }.pickerStyle(.segmented)
        }
    }

    private func continuePlaying(_ game: GameRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("CONTINUE PLAYING", systemImage: "play.circle")
                .font(.caption.weight(.semibold)).tracking(1).foregroundStyle(TandemTheme.mint)
            Text(game.title).font(.title2.weight(.semibold)).lineLimit(2)
            if let played = game.lastPlayedAt {
                Text("Last played \(played, style: .relative) ago").font(.footnote).foregroundStyle(TandemTheme.muted)
            }
            Button { model.launch(game) } label: {
                Label("Continue", systemImage: "play.fill").fontWeight(.semibold)
            }.buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(22)
        .background(TandemTheme.surface, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(TandemTheme.mint.opacity(0.25)))
    }

    private var emptyLibrary: some View {
        VStack(spacing: 18) {
            Image(systemName: search.isEmpty ? "square.stack.3d.up" : "magnifyingglass")
                .font(.system(size: 42, weight: .ultraLight)).foregroundStyle(TandemTheme.mint)
            Text(favoritesOnly ? "No favorites found." : (search.isEmpty ? "Make room for play." : "No games found"))
                .font(.title3.weight(.semibold))
            Text(favoritesOnly ? "Touch and hold a game, then choose Add to Favorites." : (search.isEmpty ? "Import a game file from Files to start your collection." : "Try another title or system."))
                .font(.subheadline).foregroundStyle(TandemTheme.muted)
                .multilineTextAlignment(.center).frame(maxWidth: 280)
            if search.isEmpty && !favoritesOnly {
                Button { importing = true } label: {
                    Label("Import a game", systemImage: "plus").font(.subheadline.weight(.semibold)).padding(.horizontal, 14).padding(.vertical, 8)
                }.buttonStyle(.borderedProminent).foregroundStyle(TandemTheme.background).disabled(model.isImporting)
            }
        }.frame(maxWidth: .infinity).padding(.vertical, 64)
            .background(TandemTheme.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 24))
    }
}

private struct GameCard: View {
    let game: GameRecord
    let coverURL: URL
    let coverVersion: Int
    let play: () -> Void
    @State private var cover: UIImage?
    var body: some View {
        Button(action: play) {
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18).fill(TandemTheme.surface)
                    if let cover {
                        GeometryReader { proxy in
                            Image(uiImage: cover).resizable().scaledToFill()
                                .frame(width: proxy.size.width, height: proxy.size.height).clipped()
                        }.clipShape(RoundedRectangle(cornerRadius: 18))
                    } else {
                        VStack(spacing: 20) {
                            SystemMark(is3DS: game.system == .nintendo3DS)
                            Text(game.title.prefix(2).uppercased())
                                .font(.system(size: 42, weight: .light, design: .rounded)).foregroundStyle(.primary.opacity(0.7))
                        }
                    }
                    VStack {
                        HStack {
                            Text(game.system == .nintendo3DS ? "3DS" : "SWITCH")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1)
                            Spacer()
                            Image(systemName: "play.fill").font(.system(size: 9))
                        }.foregroundStyle(TandemTheme.muted)
                        Spacer()
                    }.padding(16)
                }.aspectRatio(0.94, contentMode: .fit)
                Text(game.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(ByteCountFormatter.string(fromByteCount: game.byteCount, countStyle: .file))
                    .font(.caption).foregroundStyle(TandemTheme.muted)
            }
        }.buttonStyle(.plain).accessibilityLabel("Play \(game.title), \(game.system.displayName)")
            .task(id: coverVersion) { cover = UIImage(contentsOfFile: coverURL.path) }
    }
}
