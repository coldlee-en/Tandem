import Foundation
import XCTest
@testable import EmulationKit

final class ThreeDSKeyFileTests: XCTestCase {
    // Synthetic parser values; these are not console keys.
    private let generator = String(repeating: "0", count: 32)
    private let key = String(repeating: "1", count: 32)
    private var valid: String { "generatorConstant=\(generator)\nslot0x2CKeyX=\(key)\n" }

    func testLegacyFileNormalizesAndKeepsOriginalData() throws {
        let input = Data(("# local dump\n" + valid).utf8)
        XCTAssertEqual(String(decoding: try ThreeDSKeyFile.normalize(input), as: UTF8.self), ":AES\n" + valid)
        XCTAssertTrue(String(decoding: input, as: UTF8.self).hasPrefix("# local dump"))
    }

    func testSectionedFileImportsOnlyNCCHAESKeys() throws {
        let input = ":RSA\nunrelated=private-material\n:AES\n" + valid + ":ECC\nother=ignored\n"
        let output = try ThreeDSKeyFile.normalize(Data(input.utf8))
        XCTAssertEqual(String(decoding: output, as: UTF8.self), ":AES\n" + valid)
    }

    func testWhitespaceBOMCommentsAndLowercaseSlotNormalize() throws {
        let input = "\u{FEFF} generatorConstant = \(generator) # comment\r\nslot0x2cKeyX = \(key)\r\n"
        XCTAssertEqual(String(decoding: try ThreeDSKeyFile.normalize(Data(input.utf8)), as: UTF8.self), ":AES\n" + valid)
    }

    func testMissingRequiredFieldsRejected() {
        for input in ["slot0x2CKeyX=\(key)", "generatorConstant=\(generator)", ":RSA\n" + valid] {
            XCTAssertThrowsError(try ThreeDSKeyFile.normalize(Data(input.utf8)))
        }
    }

    func testInvalidHexAndDuplicateAliasesRejectedWithoutLeakingKeys() {
        for value in [String(repeating: "z", count: 32), String(repeating: "2", count: 31)] {
            XCTAssertThrowsError(try ThreeDSKeyFile.normalize(Data("generatorConstant=\(generator)\nslot0x2CKeyX=\(value)".utf8))) { error in
                XCTAssertFalse(error.localizedDescription.contains(value))
            }
        }
        XCTAssertThrowsError(try ThreeDSKeyFile.normalize(Data((valid + "slot0x2cKeyX=\(key)\n").utf8)))
    }

    func testInvalidTextAndOversizedFilesRejected() {
        for data in [Data(), Data([0xFF]), Data((valid + "\0").utf8), Data(repeating: 32, count: 1_048_576)] {
            XCTAssertThrowsError(try ThreeDSKeyFile.normalize(data))
        }
    }

    func testSeedDatabaseCountAndLengthChecked() throws {
        var data = Data(repeating: 0, count: 48)
        data[0] = 1
        try ThreeDSKeyFile.validateSeedDatabase(data)
        XCTAssertThrowsError(try ThreeDSKeyFile.validateSeedDatabase(data.dropLast()))
        data[0] = 2
        XCTAssertThrowsError(try ThreeDSKeyFile.validateSeedDatabase(data))
        XCTAssertThrowsError(try ThreeDSKeyFile.validateSeedDatabase(Data(repeating: 255, count: 16)))
    }
}
