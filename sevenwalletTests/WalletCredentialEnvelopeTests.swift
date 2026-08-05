import Foundation
import Testing
@testable import sevenwallet

struct WalletCredentialEnvelopeTests {
    @Test(arguments: [16, 32])
    func roundTripsMnemonicEntropy(byteCount: Int) throws {
        let payload = WalletCredentialPayload(
            kind: .mnemonicEntropy,
            bytes: Data(repeating: 0xA5, count: byteCount)
        )

        let encoded = try WalletCredentialEnvelope.encode(payload)
        let decoded = try WalletCredentialEnvelope.decode(encoded)

        #expect(decoded.kind == .mnemonicEntropy)
        #expect(decoded.bytes == payload.bytes)
    }

    @Test func roundTripsPrivateKey() throws {
        let payload = WalletCredentialPayload(
            kind: .privateKey,
            bytes: Data(repeating: 0x5A, count: 32)
        )

        let encoded = try WalletCredentialEnvelope.encode(payload)
        let decoded = try WalletCredentialEnvelope.decode(encoded)

        #expect(decoded.kind == .privateKey)
        #expect(decoded.bytes == payload.bytes)
    }

    @Test func rejectsUnknownVersion() {
        let data = Data([2, WalletCredentialKind.privateKey.rawValue])
            + Data(repeating: 0, count: 32)

        #expect(throws: WalletCredentialError.corruptCredential) {
            try WalletCredentialEnvelope.decode(data)
        }
    }

    @Test func rejectsUnknownKind() {
        let data = Data([1, 0xFF]) + Data(repeating: 0, count: 32)

        #expect(throws: WalletCredentialError.corruptCredential) {
            try WalletCredentialEnvelope.decode(data)
        }
    }

    @Test(arguments: [0, 15, 17, 31, 33])
    func rejectsInvalidMnemonicEntropyLength(byteCount: Int) {
        let data = Data([1, WalletCredentialKind.mnemonicEntropy.rawValue])
            + Data(repeating: 0, count: byteCount)

        #expect(throws: WalletCredentialError.corruptCredential) {
            try WalletCredentialEnvelope.decode(data)
        }
    }

    @Test(arguments: [0, 31, 33])
    func rejectsInvalidPrivateKeyLength(byteCount: Int) {
        let data = Data([1, WalletCredentialKind.privateKey.rawValue])
            + Data(repeating: 0, count: byteCount)

        #expect(throws: WalletCredentialError.corruptCredential) {
            try WalletCredentialEnvelope.decode(data)
        }
    }

    @Test func rejectsEncodingInvalidPayload() {
        let payload = WalletCredentialPayload(
            kind: .privateKey,
            bytes: Data(repeating: 0, count: 31)
        )

        #expect(throws: WalletCredentialError.corruptCredential) {
            try WalletCredentialEnvelope.encode(payload)
        }
    }
}
