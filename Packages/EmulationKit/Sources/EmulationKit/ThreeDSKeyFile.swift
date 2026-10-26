import Foundation

/// Normalizes console-supplied Citra AES entries to Cytrus's keys.txt format.
/// Error text never includes key values.
public enum ThreeDSKeyFile {
    public enum ImportError: LocalizedError {
        case invalidText, invalidEntry, missingRequiredKeys, invalidSeedDatabase
        public var errorDescription: String? {
            switch self {
            case .invalidText: "Choose a UTF-8 AES keys text file smaller than 1 MB."
            case .invalidEntry: "The AES file contains an invalid or duplicate key entry. Each AES value must contain exactly 32 hexadecimal characters."
            case .missingRequiredKeys: "The AES file needs generatorConstant and slot0x2CKeyX from your console dump."
            case .invalidSeedDatabase: "Choose a valid seeddb.bin database with a complete 16-byte header and 32-byte seed entries."
            }
        }
    }

    public static func normalize(_ data: Data) throws -> Data {
        guard !data.isEmpty, data.count < 1_048_576,
              var text = String(data: data, encoding: .utf8), !text.contains("\0") else {
            throw ImportError.invalidText
        }
        if text.first == "\u{FEFF}" { text.removeFirst() }
        var values: [String: String] = [:]
        let hasSections = text.split(whereSeparator: \.isNewline).contains {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix(":")
        }
        var inAES = !hasSections
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
                .trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix(":") { inAES = line == ":AES"; continue }
            guard inAES else { continue }
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { throw ImportError.invalidEntry }
            let originalName = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            // Import only AES slots used for NCCH, not unrelated RSA/OTP material.
            let supported = ["generatorConstant", "slot0x2CKeyX", "slot0x25KeyX", "slot0x18KeyX", "slot0x1BKeyX"]
            guard let name = supported.first(where: { $0.lowercased() == originalName.lowercased() }) else { continue }
            guard values[name] == nil, value.utf8.count == 32,
                  value.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else {
                throw ImportError.invalidEntry
            }
            values[name] = value
        }
        guard values["generatorConstant"] != nil, values["slot0x2CKeyX"] != nil else {
            throw ImportError.missingRequiredKeys
        }
        let names = ["generatorConstant", "slot0x2CKeyX", "slot0x25KeyX", "slot0x18KeyX", "slot0x1BKeyX"]
        let lines = names.compactMap { name in values[name].map { "\(name)=\($0)" } }
        return Data((":AES\n" + lines.joined(separator: "\n") + "\n").utf8)
    }

    public static func validateSeedDatabase(_ data: Data) throws {
        guard data.count >= 16, data.count <= 32 * 1_048_576 else { throw ImportError.invalidSeedDatabase }
        let count = data.prefix(4).enumerated().reduce(UInt64(0)) { $0 | (UInt64($1.element) << ($1.offset * 8)) }
        guard UInt64(data.count) == 16 + count * 32 else { throw ImportError.invalidSeedDatabase }
    }
}
