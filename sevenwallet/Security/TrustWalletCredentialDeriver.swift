import Foundation
import WalletCore

nonisolated struct TrustWalletCredentialDeriver: WalletCredentialDeriving {
    private static let ethereumDerivationPath = "m/44'/60'/0'/0/0"

    func prepare(_ input: WalletSecretInput) throws -> PreparedWalletCredential {
        switch input {
        case .recoveryPhrase(let value):
            try prepareRecoveryPhrase(value)
        case .privateKey(let value):
            try preparePrivateKey(value)
        }
    }

    private func prepareRecoveryPhrase(_ value: String) throws -> PreparedWalletCredential {
        let words = value
            .precomposedStringWithCompatibilityMapping
            .lowercased()
            .split(whereSeparator: \Character.isWhitespace)
        guard words.count == 12 || words.count == 24 else {
            throw WalletCredentialError.invalidRecoveryPhrase
        }
        let phrase = words.joined(separator: " ")
        guard let wallet = HDWallet(mnemonic: phrase, passphrase: "") else {
            throw WalletCredentialError.invalidRecoveryPhrase
        }
        let privateKey = wallet.getKey(
            coin: .ethereum,
            derivationPath: Self.ethereumDerivationPath
        )
        let address = try normalizedAddress(for: privateKey)
        return PreparedWalletCredential(
            address: address,
            payload: WalletCredentialPayload(
                kind: .mnemonicEntropy,
                bytes: wallet.entropy
            )
        )
    }

    private func preparePrivateKey(_ value: String) throws -> PreparedWalletCredential {
        var hexadecimal = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexadecimal.hasPrefix("0x") {
            hexadecimal.removeFirst(2)
        }
        guard let bytes = strictHexadecimalData(hexadecimal),
              PrivateKey.isValid(data: bytes, curve: .secp256k1),
              let privateKey = PrivateKey(data: bytes) else {
            throw WalletCredentialError.invalidPrivateKey
        }
        return PreparedWalletCredential(
            address: try normalizedAddress(for: privateKey),
            payload: WalletCredentialPayload(kind: .privateKey, bytes: bytes)
        )
    }

    private func normalizedAddress(for privateKey: PrivateKey) throws -> EVMAddress {
        let rawAddress = CoinType.ethereum.deriveAddress(privateKey: privateKey)
        guard let address = try? EVMAddress(rawAddress) else {
            throw WalletCredentialError.storageFailure
        }
        return address
    }

    private func strictHexadecimalData(_ value: String) -> Data? {
        guard value.utf8.count == 64 else { return nil }
        var bytes = Data(capacity: 32)
        var index = value.startIndex
        for _ in 0..<32 {
            let next = value.index(index, offsetBy: 2)
            guard let byte = UInt8(value[index..<next], radix: 16) else {
                return nil
            }
            bytes.append(byte)
            index = next
        }
        return bytes
    }
}
