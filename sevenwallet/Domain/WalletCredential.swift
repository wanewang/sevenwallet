import Foundation

nonisolated enum WalletImportMethod: String, CaseIterable, Hashable, Identifiable, Sendable {
    case watchAddress
    case recoveryPhrase
    case privateKey

    var id: String { rawValue }
}

nonisolated struct WalletCredentialReference: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: UUID

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

nonisolated enum WalletSecretInput: Sendable {
    case recoveryPhrase(String)
    case privateKey(String)
}

nonisolated enum WalletCredentialKind: UInt8, Equatable, Sendable {
    case mnemonicEntropy = 1
    case privateKey = 2
}

nonisolated protocol WalletCredentialDeriving: Sendable {
    func prepare(_ input: WalletSecretInput) throws -> PreparedWalletCredential
}

nonisolated struct WalletCredentialPayload: Sendable {
    let kind: WalletCredentialKind
    let bytes: Data

    init(kind: WalletCredentialKind, bytes: Data) {
        self.kind = kind
        self.bytes = bytes
    }
}

nonisolated struct PreparedWalletCredential: Sendable {
    let address: EVMAddress
    let payload: WalletCredentialPayload
}

nonisolated enum WalletCredentialPresence: Equatable, Sendable {
    case present
    case missing
}

nonisolated protocol WalletCredentialVault: Sendable {
    func isProtectionAvailable() async -> Bool

    func presence(
        of reference: WalletCredentialReference
    ) async throws -> WalletCredentialPresence

    func store(
        _ payload: WalletCredentialPayload,
        for reference: WalletCredentialReference
    ) async throws

    func read(
        for reference: WalletCredentialReference
    ) async throws -> WalletCredentialPayload

    func delete(
        for reference: WalletCredentialReference
    ) async throws
}

nonisolated enum WalletCredentialError: LocalizedError, Equatable, Sendable {
    case invalidRecoveryPhrase
    case invalidPrivateKey
    case protectionUnavailable
    case authenticationCancelled
    case authenticationFailed
    case credentialAlreadyImported
    case credentialNotFound
    case corruptCredential
    case storageFailure
    case statusUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidRecoveryPhrase:
            "Enter a valid 12- or 24-word English recovery phrase."
        case .invalidPrivateKey:
            "Enter a valid 64-character Ethereum private key."
        case .protectionUnavailable:
            "Enable a device passcode before importing wallet credentials."
        case .authenticationCancelled:
            "Authentication was cancelled."
        case .authenticationFailed:
            "Unable to verify device ownership."
        case .credentialAlreadyImported:
            "This wallet has already been imported."
        case .credentialNotFound:
            "The stored wallet credential is unavailable."
        case .corruptCredential:
            "The stored wallet credential cannot be read."
        case .storageFailure:
            "Unable to store wallet credentials securely."
        case .statusUnavailable:
            "Unable to verify stored wallet credentials."
        }
    }
}
