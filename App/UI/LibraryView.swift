import SwiftUI
import UIKit
import UniformTypeIdentifiers
import EmulationKit

@MainActor
struct LibraryView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var session: EmulationSession
    @ObservedObject private var collections: LibraryCollectionsStore
    @State private var search = ""
    @State private var importing = false
    @State private var showingSettings = false
    @State private var coverTarget: GameRecord?
    @State private var importingCover = false
    @State private var favoritesOnly = false
    @State private var selectedCollection: UUID?
    @State private var showingCollections = false
    @State private var detailTarget: GameRecord?
    @State private var pendingLaunch: GameRecord?
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
        self.collections = model.collections
    }

    private var filteredGames: [GameRecord] {
        model.games.filter { game in
            (!favoritesOnly || favoriteIDs.contains(game.id.uuidString))
                && game.system == .nintendo3DS
                && (selectedCollection.map { collections.catalog.contains(gameID: game.id, collectionID: $0) } ?? true)
                && (search.isEmpty || game.title.localizedCaseInsensitiveContains(search))
        }.sorted { ($0.lastPlayedAt ?? $0.importedAt) > ($1.lastPlayedAt ?? $1.importedAt) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    introduction
                    if search.isEmpty, !favoritesOnly, selectedCollection == nil,
                       let recent = model.games.filter({ $0.system == .nintendo3DS && $0.lastPlayedAt != nil }).max(by: { ($0.lastPlayedAt ?? .distantPast) < ($1.lastPlayedAt ?? .distantPast) }) {
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
                                GameCard(game: game, coverURL: model.coverURL(for: game), coverVersion: model.coverVersions[game.id, default: 0], isFavorite: favoriteIDs.contains(game.id.uuidString), play: { model.launch(game) }, details: { detailTarget = game })
                                    .contextMenu {
                                        Button("Play", systemImage: "play.fill") { model.launch(game) }
                                        Button("Details and collections", systemImage: "info.circle") { detailTarget = game }
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
        .sheet(isPresented: $showingCollections) { CollectionsView(model: model, store: collections) }
        .sheet(item: $detailTarget, onDismiss: {
            if let game = pendingLaunch {
                pendingLaunch = nil
                model.launch(game)
            }
        }) { game in
            GameDetailsView(game: game, model: model, collections: collections, isFavorite: Binding {
                favoriteIDs.contains(game.id.uuidString)
            } set: { value in
                if value != favoriteIDs.contains(game.id.uuidString) { toggleFavorite(game) }
            }, play: {
                pendingLaunch = game
                detailTarget = nil
            })
        }
        .onChange(of: collections.catalog.collections.map(\.id)) { _, ids in
            if let selectedCollection, !ids.contains(selectedCollection) { self.selectedCollection = nil }
        }
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
                Button("Collections", systemImage: "folder") { showingCollections = true }
                    .buttonStyle(.bordered)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    filterButton("All games", icon: "square.grid.2x2", selected: !favoritesOnly && selectedCollection == nil) {
                        favoritesOnly = false; selectedCollection = nil
                    }
                    filterButton("Favorites", icon: "heart", selected: favoritesOnly) {
                        favoritesOnly = true; selectedCollection = nil
                    }
                    ForEach(collections.catalog.collections) { collection in
                        filterButton(collection.name, icon: "folder", selected: selectedCollection == collection.id) {
                            favoritesOnly = false; selectedCollection = collection.id
                        }
                    }
                }
            }
            if let message = collections.loadError { Text(message).font(.footnote).foregroundStyle(TandemTheme.muted) }
        }
    }

    private func filterButton(_ title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: icon).lineLimit(1) }
            .buttonStyle(.bordered)
            .tint(selected ? TandemTheme.mint : TandemTheme.muted)
            .accessibilityValue(selected ? "Selected" : "")
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
            Button("Game details", systemImage: "info.circle") { detailTarget = game }.buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(22)
        .background(TandemTheme.surface, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(TandemTheme.mint.opacity(0.25)))
    }

    private var emptyLibrary: some View {
        VStack(spacing: 18) {
            Image(systemName: search.isEmpty ? "square.stack.3d.up" : "magnifyingglass")
                .font(.system(size: 42, weight: .ultraLight)).foregroundStyle(TandemTheme.mint)
            Text(!search.isEmpty ? "No matching games." : (selectedCollection != nil ? "No games in this collection." : (favoritesOnly ? "No favorites found." : "Make room for play.")))
                .font(.title3.weight(.semibold))
            Text(!search.isEmpty ? "Try another title or clear your search." : (selectedCollection != nil ? "Use Collections to choose games for this collection." : (favoritesOnly ? "Open a game’s details to mark it as a favorite." : "Import a game file from Files to start your library.")))
                .font(.subheadline).foregroundStyle(TandemTheme.muted)
                .multilineTextAlignment(.center).frame(maxWidth: 280)
            if search.isEmpty && !favoritesOnly && selectedCollection == nil {
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
    let isFavorite: Bool
    let play: () -> Void
    let details: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: play) {
                GameArtwork(game: game, coverURL: coverURL, coverVersion: coverVersion)
                    .aspectRatio(0.94, contentMode: .fit)
                    .overlay(alignment: .topTrailing) {
                        if isFavorite {
                            Image(systemName: "heart.fill").foregroundStyle(TandemTheme.mint)
                                .padding(9).background(.ultraThinMaterial, in: Circle()).padding(10)
                                .accessibilityHidden(true)
                        }
                    }
            }.buttonStyle(.plain).accessibilityLabel("Play \(game.title)")
            HStack(alignment: .top, spacing: 6) {
                Text(game.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: details) {
                    Image(systemName: "ellipsis.circle").frame(width: 44, height: 44)
                }.buttonStyle(.plain).foregroundStyle(TandemTheme.mint)
                    .accessibilityLabel("Details and collections for \(game.title)")
            }
            Text(ByteCountFormatter.string(fromByteCount: game.byteCount, countStyle: .file))
                .font(.caption).foregroundStyle(TandemTheme.muted)
        }
    }
}
