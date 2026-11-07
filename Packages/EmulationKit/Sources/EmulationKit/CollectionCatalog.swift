import Foundation

public enum CollectionError: LocalizedError {
    case invalidName, duplicateName, missingCollection, invalidData
    public var errorDescription: String? {
        switch self {
        case .invalidName: return "Use a collection name of 1–64 characters on one line."
        case .duplicateName: return "A collection with that name already exists."
        case .missingCollection: return "This collection no longer exists."
        case .invalidData: return "Collection information could not be read. Your games and saves are unaffected."
        }
    }
}

public struct GameCollection: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public fileprivate(set) var name: String
    public fileprivate(set) var gameIDs: [UUID]
}

/// Organization metadata only: no ROM paths, file access, or save-data operations.
public struct CollectionCatalog: Equatable {
    public static let storageKey = "libraryCollections.v1"
    public private(set) var collections: [GameCollection] = []
    private struct Document: Codable {
        let version: Int
        let collections: [GameCollection]
    }

    public init() {}

    public init(serialized: String) throws {
        if serialized.isEmpty { return }
        guard let document = try? JSONDecoder().decode(Document.self, from: Data(serialized.utf8)),
              document.version == 1,
              Set(document.collections.map(\.id)).count == document.collections.count else {
            throw CollectionError.invalidData
        }
        var names: Set<String> = []
        for collection in document.collections {
            guard (try? Self.cleanName(collection.name)) == collection.name,
                  names.insert(Self.nameKey(collection.name)).inserted,
                  Set(collection.gameIDs).count == collection.gameIDs.count else {
                throw CollectionError.invalidData
            }
        }
        collections = document.collections
    }

    public func serialized() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Document(version: 1, collections: collections))
        return String(decoding: data, as: UTF8.self)
    }

    @discardableResult
    public mutating func create(name: String) throws -> UUID {
        let cleaned = try Self.cleanName(name)
        guard !collections.contains(where: { Self.nameKey($0.name) == Self.nameKey(cleaned) }) else {
            throw CollectionError.duplicateName
        }
        let id = UUID()
        collections.append(GameCollection(id: id, name: cleaned, gameIDs: []))
        return id
    }

    public mutating func rename(_ id: UUID, to name: String) throws {
        let index = try index(for: id)
        let cleaned = try Self.cleanName(name)
        guard !collections.contains(where: { $0.id != id && Self.nameKey($0.name) == Self.nameKey(cleaned) }) else {
            throw CollectionError.duplicateName
        }
        collections[index].name = cleaned
    }

    public mutating func remove(_ id: UUID) throws {
        let index = try index(for: id)
        collections.remove(at: index)
    }

    public mutating func setMembership(gameID: UUID, collectionID: UUID, included: Bool) throws {
        let index = try index(for: collectionID)
        if included {
            if !collections[index].gameIDs.contains(gameID) {
                collections[index].gameIDs.append(gameID)
            }
        } else {
            collections[index].gameIDs.removeAll { $0 == gameID }
        }
    }

    public func contains(gameID: UUID, collectionID: UUID) -> Bool {
        collections.first(where: { $0.id == collectionID })?.gameIDs.contains(gameID) ?? false
    }

    private func index(for id: UUID) throws -> Int {
        guard let index = collections.firstIndex(where: { $0.id == id }) else { throw CollectionError.missingCollection }
        return index
    }

    private static func cleanName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw CollectionError.invalidName
        }
        let cleaned = trimmed.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !cleaned.isEmpty, cleaned.count <= 64 else { throw CollectionError.invalidName }
        return cleaned
    }

    private static func nameKey(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}
