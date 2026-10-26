import Foundation

public enum GameSystem: String, Codable, CaseIterable, Identifiable, Sendable {
    case nintendo3DS
    case nintendoSwitch

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .nintendo3DS: "Nintendo 3DS"
        case .nintendoSwitch: "Nintendo Switch"
        }
    }

    /// Importable files. CIA archives must be installed through a compatible core.
    public var supportedExtensions: [String] {
        switch self {
        case .nintendo3DS: ["3ds", "cci", "cxi", "3dsx"]
        case .nintendoSwitch: ["nro", "nso", "xci", "nsp"]
        }
    }

    public static func system(forFileExtension fileExtension: String) -> GameSystem? {
        allCases.first { $0.supportedExtensions.contains(fileExtension.lowercased()) }
    }
}

public struct GameRecord: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public let system: GameSystem
    public let relativePath: String
    public let byteCount: Int64
    public let importedAt: Date
    public var lastPlayedAt: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        system: GameSystem,
        relativePath: String,
        byteCount: Int64,
        importedAt: Date = Date(),
        lastPlayedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.system = system
        self.relativePath = relativePath
        self.byteCount = byteCount
        self.importedAt = importedAt
        self.lastPlayedAt = lastPlayedAt
    }
}
