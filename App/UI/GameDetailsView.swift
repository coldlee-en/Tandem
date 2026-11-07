import SwiftUI
import UIKit
import EmulationKit

struct GameArtwork: View {
    let game: GameRecord
    let coverURL: URL
    let coverVersion: Int
    @State private var cover: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18).fill(TandemTheme.surface)
            if let cover {
                GeometryReader { proxy in
                    Image(uiImage: cover).resizable().scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height).clipped()
                }
            } else {
                VStack(spacing: 16) {
                    SystemMark(is3DS: true)
                    Text(game.title.prefix(2).uppercased())
                        .font(.system(size: 42, weight: .light, design: .rounded))
                        .foregroundStyle(.primary.opacity(0.7))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .task(id: "\(game.id)-\(coverVersion)") { cover = UIImage(contentsOfFile: coverURL.path) }
        .accessibilityHidden(true)
    }
}

@MainActor
struct GameDetailsView: View {
    let game: GameRecord
    @ObservedObject var model: AppModel
    @ObservedObject var collections: LibraryCollectionsStore
    @Binding var isFavorite: Bool
    let play: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var importingCover = false
    @State private var showingCollections = false
    @State private var removing = false

    private var collectionNames: [String] {
        collections.catalog.collections.filter { $0.gameIDs.contains(game.id) }.map(\.name)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    GameArtwork(game: game, coverURL: model.coverURL(for: game), coverVersion: model.coverVersions[game.id, default: 0])
                        .frame(height: 240)
                    Text(game.title).font(.largeTitle.weight(.semibold))
                    HStack {
                        Button("Play", systemImage: "play.fill", action: play)
                            .buttonStyle(.borderedProminent)
                            .disabled(model.isManagingSystemData || model.session.game != nil)
                        Button(isFavorite ? "Favorited" : "Favorite", systemImage: isFavorite ? "heart.fill" : "heart") {
                            isFavorite.toggle()
                        }.buttonStyle(.bordered)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Collections", systemImage: "folder").font(.headline)
                        Text(collections.loadError ?? (collectionNames.isEmpty ? "Not in a collection" : collectionNames.joined(separator: ", ")))
                            .foregroundStyle(TandemTheme.muted)
                        Button("Choose collections", systemImage: "folder.badge.plus") { showingCollections = true }
                            .buttonStyle(.bordered)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
                        .background(TandemTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                    VStack(spacing: 14) {
                        LabeledContent("System", value: "Nintendo 3DS")
                        LabeledContent("File format", value: URL(fileURLWithPath: game.relativePath).pathExtension.uppercased())
                        LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: game.byteCount, countStyle: .file))
                        LabeledContent("Added") { Text(game.importedAt, format: .dateTime.month().day().year()) }
                        LabeledContent("Last played") {
                            if let date = game.lastPlayedAt { Text(date, format: .dateTime.month().day().hour().minute()) }
                            else { Text("Not played yet") }
                        }
                    }.font(.subheadline).padding(20)
                        .background(TandemTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Artwork").font(.headline)
                        Button("Choose cover image", systemImage: "photo") { importingCover = true }
                        Button("Remove cover image", systemImage: "photo.badge.minus") { model.removeCover(for: game) }
                    }.buttonStyle(.bordered)
                    Button("Remove from library", systemImage: "trash", role: .destructive) { removing = true }
                        .disabled(model.session.game?.id == game.id)
                }.padding(24).frame(maxWidth: 700).frame(maxWidth: .infinity)
            }
            .background(TandemTheme.background)
            .navigationTitle("Game details").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
            .sheet(isPresented: $showingCollections) { GameCollectionsView(game: game, store: collections) }
            .fileImporter(isPresented: $importingCover, allowedContentTypes: [.image], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls): if let url = urls.first { model.importCover(url, for: game) }
                case .failure(let error): model.errorMessage = error.localizedDescription
                }
            }
            .confirmationDialog("Remove this game?", isPresented: $removing, titleVisibility: .visible) {
                Button("Remove game", role: .destructive) { model.remove(game); dismiss() }
                Button("Cancel", role: .cancel) {}
            } message: { Text("This removes the imported game file and its cover. Existing in-game saves and save states are kept.") }
            .alert("Tandem", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                Button("OK") { model.errorMessage = nil }
            } message: { Text(model.errorMessage ?? "") }
        }.tint(TandemTheme.mint)
    }
}
