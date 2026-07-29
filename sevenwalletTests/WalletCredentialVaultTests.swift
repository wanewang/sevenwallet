import Foundation
import LocalAuthentication
import Security
import Testing
@testable import sevenwallet

struct WalletCredentialVaultTests {
    private let reference = WalletCredentialReference(
        rawValue: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    )

    @Test func blocksStoreWhenDeviceProtectionIsUnavailable() async {
        let authenticator = StubDeviceOwnerAuthenticator(isAvailable: false)
        let keychain = StubWalletCredentialKeychain()
        let vault = KeychainWalletCredentialVault(
            authenticator: authenticator,
            keychain: keychain
        )

        await #expect(throws: WalletCredentialError.protectionUnavailable) {
            try await vault.store(makePayload(), for: reference)
        }
        #expect(await authenticator.calls == [.availability])
        #expect(await keychain.calls.isEmpty)
    }

    @Test(arguments: [
        WalletCredentialError.authenticationCancelled,
        WalletCredentialError.authenticationFailed
    ])
    func preservesAuthenticationErrorWithoutWriting(
        error: WalletCredentialError
    ) async {
        let authenticator = StubDeviceOwnerAuthenticator(error: error)
        let keychain = StubWalletCredentialKeychain()
        let vault = KeychainWalletCredentialVault(
            authenticator: authenticator,
            keychain: keychain
        )

        await #expect(throws: error) {
            try await vault.store(makePayload(), for: reference)
        }
        #expect(await keychain.calls.isEmpty)
    }

    @Test func mapsLocalAuthenticationCancellationAndFailure() {
        #expect(
            LocalDeviceOwnerAuthenticator.map(.userCancel)
                == .authenticationCancelled
        )
        #expect(
            LocalDeviceOwnerAuthenticator.map(.systemCancel)
                == .authenticationCancelled
        )
        #expect(
            LocalDeviceOwnerAuthenticator.map(.authenticationFailed)
                == .authenticationFailed
        )
        #expect(
            LocalDeviceOwnerAuthenticator.map(.passcodeNotSet)
                == .protectionUnavailable
        )
    }

    @Test func mapsDuplicateItemToNonSecretStorageFailure() async {
        let keychain = StubWalletCredentialKeychain(addStatus: errSecDuplicateItem)
        let vault = KeychainWalletCredentialVault(
            authenticator: StubDeviceOwnerAuthenticator(),
            keychain: keychain
        )
        let payload = makePayload(byte: 0xAB)

        await #expect(throws: WalletCredentialError.storageFailure) {
            try await vault.store(payload, for: reference)
        }

        let message = WalletCredentialError.storageFailure.localizedDescription
        let secretHex = String(repeating: "ab", count: 32)
        #expect(!message.localizedCaseInsensitiveContains(secretHex))
        #expect(!message.localizedCaseInsensitiveContains("private key"))
    }

    @Test(arguments: [errSecSuccess, errSecInteractionNotAllowed])
    func treatsAccessibleAndLockedItemsAsPresent(status: OSStatus) async throws {
        let keychain = StubWalletCredentialKeychain(presenceStatus: status)
        let vault = KeychainWalletCredentialVault(
            authenticator: StubDeviceOwnerAuthenticator(),
            keychain: keychain
        )

        let presence = try await vault.presence(of: reference)

        #expect(presence == .present)
    }

    @Test func mapsMissingAndIndeterminatePresence() async throws {
        let missingKeychain = StubWalletCredentialKeychain(
            presenceStatus: errSecItemNotFound
        )
        let missingVault = KeychainWalletCredentialVault(
            authenticator: StubDeviceOwnerAuthenticator(),
            keychain: missingKeychain
        )
        #expect(try await missingVault.presence(of: reference) == .missing)

        let failedKeychain = StubWalletCredentialKeychain(
            presenceStatus: errSecNotAvailable
        )
        let failedVault = KeychainWalletCredentialVault(
            authenticator: StubDeviceOwnerAuthenticator(),
            keychain: failedKeychain
        )
        await #expect(throws: WalletCredentialError.statusUnavailable) {
            try await failedVault.presence(of: reference)
        }
    }

    @Test func readsAndDecodesCredential() async throws {
        let payload = makePayload()
        let keychain = StubWalletCredentialKeychain(
            readStatus: errSecSuccess,
            readData: try WalletCredentialEnvelope.encode(payload)
        )
        let vault = KeychainWalletCredentialVault(
            authenticator: StubDeviceOwnerAuthenticator(),
            keychain: keychain
        )

        let result = try await vault.read(for: reference)

        #expect(result.kind == payload.kind)
        #expect(result.bytes == payload.bytes)
    }

    @Test(arguments: [
        (errSecItemNotFound, WalletCredentialError.credentialNotFound),
        (errSecUserCanceled, WalletCredentialError.authenticationCancelled),
        (errSecAuthFailed, WalletCredentialError.authenticationFailed)
    ])
    func mapsReadFailures(
        status: OSStatus,
        error: WalletCredentialError
    ) async {
        let keychain = StubWalletCredentialKeychain(readStatus: status)
        let vault = KeychainWalletCredentialVault(
            authenticator: StubDeviceOwnerAuthenticator(),
            keychain: keychain
        )

        await #expect(throws: error) {
            try await vault.read(for: reference)
        }
    }

    @Test func authenticatesDeleteAndMapsMissingItem() async {
        let authenticator = StubDeviceOwnerAuthenticator()
        let keychain = StubWalletCredentialKeychain(
            deleteStatus: errSecItemNotFound
        )
        let vault = KeychainWalletCredentialVault(
            authenticator: authenticator,
            keychain: keychain
        )

        await #expect(throws: WalletCredentialError.credentialNotFound) {
            try await vault.delete(for: reference)
        }
        #expect(await authenticator.calls == [.availability, .authenticate])
        #expect(await keychain.calls == [.delete])
    }

    private func makePayload(byte: UInt8 = 0x11) -> WalletCredentialPayload {
        WalletCredentialPayload(
            kind: .privateKey,
            bytes: Data(repeating: byte, count: 32)
        )
    }
}

private enum StubAuthenticatorCall: Equatable, Sendable {
    case availability
    case authenticate
}

private actor StubDeviceOwnerAuthenticator: DeviceOwnerAuthenticating {
    private let available: Bool
    private let error: WalletCredentialError?
    private(set) var calls: [StubAuthenticatorCall] = []

    init(
        isAvailable: Bool = true,
        error: WalletCredentialError? = nil
    ) {
        self.available = isAvailable
        self.error = error
    }

    func isAvailable() -> Bool {
        calls.append(.availability)
        return available
    }

    func authenticate(reason: String) throws {
        calls.append(.authenticate)
        if let error { throw error }
    }
}

private enum StubKeychainCall: Equatable, Sendable {
    case add
    case read
    case delete
    case presence
}

private actor StubWalletCredentialKeychain: WalletCredentialKeychainAccessing {
    private let addStatus: OSStatus
    private let readStatus: OSStatus
    private let readData: Data?
    private let deleteStatus: OSStatus
    private let presenceStatus: OSStatus
    private(set) var calls: [StubKeychainCall] = []

    init(
        addStatus: OSStatus = errSecSuccess,
        readStatus: OSStatus = errSecItemNotFound,
        readData: Data? = nil,
        deleteStatus: OSStatus = errSecSuccess,
        presenceStatus: OSStatus = errSecItemNotFound
    ) {
        self.addStatus = addStatus
        self.readStatus = readStatus
        self.readData = readData
        self.deleteStatus = deleteStatus
        self.presenceStatus = presenceStatus
    }

    func add(data: Data, account: String) -> OSStatus {
        calls.append(.add)
        return addStatus
    }

    func read(account: String, prompt: String) -> (OSStatus, Data?) {
        calls.append(.read)
        return (readStatus, readData)
    }

    func delete(account: String) -> OSStatus {
        calls.append(.delete)
        return deleteStatus
    }

    func presence(account: String) -> OSStatus {
        calls.append(.presence)
        return presenceStatus
    }
}
