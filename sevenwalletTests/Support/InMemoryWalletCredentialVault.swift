import Foundation
@testable import sevenwallet

enum WalletCredentialVaultCall: Equatable, Hashable, Sendable {
    case protectionAvailability
    case presence(WalletCredentialReference)
    case store(WalletCredentialReference)
    case read(WalletCredentialReference)
    case delete(WalletCredentialReference)
}

enum WalletCredentialVaultOperation: Equatable, Hashable, Sendable {
    case presence
    case store
    case read
    case delete
}

actor InMemoryWalletCredentialVault: WalletCredentialVault {
    private var protectionAvailable: Bool
    private var items: [WalletCredentialReference: WalletCredentialPayload]
    private var errors: [WalletCredentialVaultCall: any Error & Sendable] = [:]
    private var operationErrors: [
        WalletCredentialVaultOperation: any Error & Sendable
    ] = [:]
    private(set) var calls: [WalletCredentialVaultCall] = []

    init(
        protectionAvailable: Bool = true,
        items: [WalletCredentialReference: WalletCredentialPayload] = [:]
    ) {
        self.protectionAvailable = protectionAvailable
        self.items = items
    }

    func isProtectionAvailable() -> Bool {
        calls.append(.protectionAvailability)
        return protectionAvailable
    }

    func presence(
        of reference: WalletCredentialReference
    ) throws -> WalletCredentialPresence {
        let call = WalletCredentialVaultCall.presence(reference)
        calls.append(call)
        if let error = errors[call] ?? operationErrors[.presence] {
            throw error
        }
        return items[reference] == nil ? .missing : .present
    }

    func store(
        _ payload: WalletCredentialPayload,
        for reference: WalletCredentialReference
    ) throws {
        let call = WalletCredentialVaultCall.store(reference)
        calls.append(call)
        if let error = errors[call] ?? operationErrors[.store] {
            throw error
        }
        items[reference] = payload
    }

    func read(
        for reference: WalletCredentialReference
    ) throws -> WalletCredentialPayload {
        let call = WalletCredentialVaultCall.read(reference)
        calls.append(call)
        if let error = errors[call] ?? operationErrors[.read] {
            throw error
        }
        guard let payload = items[reference] else {
            throw WalletCredentialError.credentialNotFound
        }
        return payload
    }

    func delete(for reference: WalletCredentialReference) throws {
        let call = WalletCredentialVaultCall.delete(reference)
        calls.append(call)
        if let error = errors[call] ?? operationErrors[.delete] {
            throw error
        }
        guard items.removeValue(forKey: reference) != nil else {
            throw WalletCredentialError.credentialNotFound
        }
    }

    func setProtectionAvailable(_ isAvailable: Bool) {
        protectionAvailable = isAvailable
    }

    func setError(
        _ error: (any Error & Sendable)?,
        for call: WalletCredentialVaultCall
    ) {
        errors[call] = error
    }

    func setError(
        _ error: (any Error & Sendable)?,
        for operation: WalletCredentialVaultOperation
    ) {
        operationErrors[operation] = error
    }

    func payload(
        for reference: WalletCredentialReference
    ) -> WalletCredentialPayload? {
        items[reference]
    }

    func resetCalls() {
        calls = []
    }
}
