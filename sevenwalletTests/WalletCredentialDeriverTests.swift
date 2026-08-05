import Foundation
import Testing
@testable import sevenwallet

struct WalletCredentialDeriverTests {
    private let deriver = TrustWalletCredentialDeriver()

    @Test func normalizesAndDerivesPublishedTwelveWordVector() throws {
        let prepared = try deriver.prepare(.recoveryPhrase(
            "  ABANDON\tabandon abandon abandon abandon abandon\n" +
            "abandon abandon abandon abandon abandon ABOUT  "
        ))

        #expect(prepared.payload.kind == .mnemonicEntropy)
        #expect(prepared.payload.bytes == Data(repeating: 0, count: 16))
        #expect(
            prepared.address == (try EVMAddress(
                "0x9858effd232b4033e47d90003d41ec34ecaeda94"
            ))
        )
    }

    @Test func acceptsPublishedTwentyFourWordVector() throws {
        let phrase = (Array(repeating: "abandon", count: 23) + ["art"])
            .joined(separator: " ")

        let prepared = try deriver.prepare(.recoveryPhrase(phrase))

        #expect(prepared.payload.kind == .mnemonicEntropy)
        #expect(prepared.payload.bytes == Data(repeating: 0, count: 32))
    }

    @Test(arguments: [
        Array(repeating: "abandon", count: 12).joined(separator: " "),
        Array(repeating: "abandon", count: 15).joined(separator: " "),
        Array(repeating: "notaword", count: 12).joined(separator: " ")
    ])
    func rejectsInvalidRecoveryPhrases(_ phrase: String) {
        #expect(throws: WalletCredentialError.invalidRecoveryPhrase) {
            try deriver.prepare(.recoveryPhrase(phrase))
        }
    }

    @Test func acceptsPrefixedUppercasePrivateKeyVector() throws {
        let input = "  0x" + String(repeating: "0", count: 63) + "1  "

        let prepared = try deriver.prepare(.privateKey(input))

        #expect(prepared.payload.kind == .privateKey)
        #expect(prepared.payload.bytes.count == 32)
        #expect(prepared.payload.bytes.last == 1)
        #expect(
            prepared.address == (try EVMAddress(
                "0x7e5f4552091a69125d5dfcb7b8c2659029395bdf"
            ))
        )
    }

    @Test(arguments: [
        "01",
        String(repeating: "g", count: 64),
        String(repeating: "0", count: 64),
        "fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141",
        // Sign prefixes parse as hex digits through `UInt8(_:radix:)` and
        // would otherwise import the unrelated key 0x0101...01.
        String(repeating: "+1", count: 32),
        String(repeating: "-1", count: 32),
        // 64 UTF-8 bytes but only 63 Characters.
        String(repeating: "a", count: 62) + "\u{00e9}",
        "\u{00e9}" + String(repeating: "a", count: 62)
    ])
    func rejectsInvalidPrivateKeys(_ key: String) {
        #expect(throws: WalletCredentialError.invalidPrivateKey) {
            try deriver.prepare(.privateKey(key))
        }
    }
}
