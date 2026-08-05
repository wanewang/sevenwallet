import Foundation

nonisolated enum WalletCredentialEnvelope {
    private static let version: UInt8 = 1
    private static let headerLength = 2

    static func encode(_ payload: WalletCredentialPayload) throws -> Data {
        guard isValidLength(payload.bytes.count, for: payload.kind) else {
            throw WalletCredentialError.corruptCredential
        }

        return Data([version, payload.kind.rawValue]) + payload.bytes
    }

    static func decode(_ data: Data) throws -> WalletCredentialPayload {
        guard data.count >= headerLength,
              data[data.startIndex] == version,
              let kind = WalletCredentialKind(
                rawValue: data[data.index(after: data.startIndex)]
              ) else {
            throw WalletCredentialError.corruptCredential
        }

        let payloadStart = data.index(data.startIndex, offsetBy: headerLength)
        let bytes = Data(data[payloadStart...])

        guard isValidLength(bytes.count, for: kind) else {
            throw WalletCredentialError.corruptCredential
        }

        return WalletCredentialPayload(kind: kind, bytes: bytes)
    }

    private static func isValidLength(
        _ byteCount: Int,
        for kind: WalletCredentialKind
    ) -> Bool {
        switch kind {
        case .mnemonicEntropy:
            byteCount == 16 || byteCount == 32
        case .privateKey:
            byteCount == 32
        }
    }
}
