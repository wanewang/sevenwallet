import Foundation
@preconcurrency import LocalAuthentication
import Security

nonisolated protocol DeviceOwnerAuthenticating: Sendable {
    func isAvailable() async -> Bool
    func authenticate(reason: String) async throws
}

nonisolated protocol WalletCredentialKeychainAccessing: Sendable {
    func add(data: Data, account: String) async throws -> OSStatus
    func read(account: String, prompt: String) async -> (OSStatus, Data?)
    func delete(account: String) async -> OSStatus
    func presence(account: String) async -> OSStatus
}

actor LocalDeviceOwnerAuthenticator: DeviceOwnerAuthenticating {
    func isAvailable() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(
            .deviceOwnerAuthentication,
            error: &error
        )
    }

    func authenticate(reason: String) async throws {
        let context = LAContext()
        var availabilityError: NSError?
        guard context.canEvaluatePolicy(
            .deviceOwnerAuthentication,
            error: &availabilityError
        ) else {
            throw WalletCredentialError.protectionUnavailable
        }

        do {
            guard try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            ) else {
                throw WalletCredentialError.authenticationFailed
            }
        } catch let error as LAError {
            throw Self.map(error.code)
        } catch let error as WalletCredentialError {
            throw error
        } catch {
            throw WalletCredentialError.authenticationFailed
        }
    }

    nonisolated static func map(
        _ code: LAError.Code
    ) -> WalletCredentialError {
        switch code {
        case .userCancel, .appCancel, .systemCancel:
            .authenticationCancelled
        case .passcodeNotSet:
            .protectionUnavailable
        default:
            .authenticationFailed
        }
    }
}

actor SystemWalletCredentialKeychain: WalletCredentialKeychainAccessing {
    private let service: String

    init(service: String) {
        self.service = service
    }

    func add(data: Data, account: String) throws -> OSStatus {
        var accessControlError: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            .userPresence,
            &accessControlError
        ) else {
            throw WalletCredentialError.protectionUnavailable
        }

        let query: [String: Any] = baseQuery(account: account).merging([
            kSecValueData as String: data,
            kSecAttrAccessControl as String: accessControl
        ]) { _, new in new }
        return SecItemAdd(query as CFDictionary, nil)
    }

    func read(account: String, prompt: String) -> (OSStatus, Data?) {
        let context = LAContext()
        context.localizedReason = prompt
        let query: [String: Any] = baseQuery(account: account).merging([
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context
        ]) { _, new in new }
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result as? Data)
    }

    func delete(account: String) -> OSStatus {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }

    func presence(account: String) -> OSStatus {
        let context = LAContext()
        context.interactionNotAllowed = true
        let query: [String: Any] = baseQuery(account: account).merging([
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context
        ]) { _, new in new }
        return SecItemCopyMatching(query as CFDictionary, nil)
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false
        ]
    }
}

actor KeychainWalletCredentialVault: WalletCredentialVault {
    private let authenticator: any DeviceOwnerAuthenticating
    private let keychain: any WalletCredentialKeychainAccessing

    init(
        service: String = "io.wane.sevenwallet.wallet-credentials",
        authenticator: any DeviceOwnerAuthenticating = LocalDeviceOwnerAuthenticator(),
        keychain: (any WalletCredentialKeychainAccessing)? = nil
    ) {
        self.authenticator = authenticator
        self.keychain = keychain ?? SystemWalletCredentialKeychain(
            service: service
        )
    }

    func isProtectionAvailable() async -> Bool {
        await authenticator.isAvailable()
    }

    func presence(
        of reference: WalletCredentialReference
    ) async throws -> WalletCredentialPresence {
        let status = await keychain.presence(account: account(for: reference))
        switch status {
        case errSecSuccess, errSecInteractionNotAllowed:
            return .present
        case errSecItemNotFound:
            return .missing
        default:
            throw WalletCredentialError.statusUnavailable
        }
    }

    func store(
        _ payload: WalletCredentialPayload,
        for reference: WalletCredentialReference
    ) async throws {
        guard await authenticator.isAvailable() else {
            throw WalletCredentialError.protectionUnavailable
        }
        try await authenticator.authenticate(
            reason: "Authenticate to securely import this wallet."
        )

        let data = try WalletCredentialEnvelope.encode(payload)
        let status = try await keychain.add(
            data: data,
            account: account(for: reference)
        )
        guard status == errSecSuccess else {
            throw Self.storageError(for: status)
        }
    }

    func read(
        for reference: WalletCredentialReference
    ) async throws -> WalletCredentialPayload {
        let (status, data) = await keychain.read(
            account: account(for: reference),
            prompt: "Authenticate to use this wallet."
        )
        guard status == errSecSuccess else {
            throw Self.readError(for: status)
        }
        guard let data else {
            throw WalletCredentialError.corruptCredential
        }
        return try WalletCredentialEnvelope.decode(data)
    }

    func delete(
        for reference: WalletCredentialReference
    ) async throws {
        guard await authenticator.isAvailable() else {
            throw WalletCredentialError.protectionUnavailable
        }
        try await authenticator.authenticate(
            reason: "Authenticate to delete this imported wallet."
        )

        let status = await keychain.delete(account: account(for: reference))
        guard status == errSecSuccess else {
            throw Self.deleteError(for: status)
        }
    }

    private func account(for reference: WalletCredentialReference) -> String {
        reference.rawValue.uuidString.lowercased()
    }

    nonisolated static func storageError(
        for status: OSStatus
    ) -> WalletCredentialError {
        switch status {
        case errSecUserCanceled:
            .authenticationCancelled
        case errSecAuthFailed:
            .authenticationFailed
        default:
            .storageFailure
        }
    }

    nonisolated static func readError(
        for status: OSStatus
    ) -> WalletCredentialError {
        switch status {
        case errSecItemNotFound:
            .credentialNotFound
        case errSecUserCanceled:
            .authenticationCancelled
        case errSecAuthFailed:
            .authenticationFailed
        default:
            .storageFailure
        }
    }

    nonisolated static func deleteError(
        for status: OSStatus
    ) -> WalletCredentialError {
        switch status {
        case errSecItemNotFound:
            .credentialNotFound
        case errSecUserCanceled:
            .authenticationCancelled
        case errSecAuthFailed:
            .authenticationFailed
        default:
            .storageFailure
        }
    }
}
