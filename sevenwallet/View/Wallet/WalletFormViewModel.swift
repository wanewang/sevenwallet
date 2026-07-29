import Foundation
import Observation

nonisolated enum WalletFormMode: Hashable, Sendable {
    case add
    case edit(SavedWallet)
}

@MainActor
@Observable
final class WalletFormViewModel {
    let mode: WalletFormMode
    var name: String
    var address: String
    var selectedColor: WalletCardColor
    private(set) var importMethod: WalletImportMethod = .watchAddress
    private(set) var secretInput = ""
    var didInteractWithName = false
    var didInteractWithAddress = false
    private(set) var didInteractWithSecret = false
    private(set) var isSubmitting = false
    private(set) var submissionError: String?

    private let deriver: any WalletCredentialDeriving

    init(
        mode: WalletFormMode,
        deriver: any WalletCredentialDeriving = TrustWalletCredentialDeriver()
    ) {
        self.mode = mode
        self.deriver = deriver
        switch mode {
        case .add:
            name = ""
            address = ""
            selectedColor = .blue
        case .edit(let wallet):
            name = wallet.name
            address = wallet.address.rawValue
            selectedColor = wallet.cardColor
        }
    }

    var title: String {
        if case .add = mode { "Add wallet" } else { "Edit wallet" }
    }

    var primaryActionTitle: String {
        switch mode {
        case .add where importMethod != .watchAddress:
            "Continue"
        case .add:
            "Add wallet"
        case .edit:
            "Save changes"
        }
    }

    var showsImportMethodPicker: Bool {
        if case .add = mode { true } else { false }
    }

    var showsSecretInput: Bool {
        showsImportMethodPicker && importMethod != .watchAddress
    }

    var isAddressEditable: Bool {
        if case .add = mode { importMethod == .watchAddress } else { false }
    }

    var showsDelete: Bool {
        if case .edit = mode { true } else { false }
    }

    var ownershipTitle: String? {
        guard case let .edit(wallet) = mode else { return nil }
        return wallet.credentialReference == nil ? "Watch only" : "Imported"
    }

    var nameError: String? {
        guard didInteractWithName,
              WalletInputValidator.validatedName(name) == nil else { return nil }
        return "Enter a wallet name."
    }

    var addressError: String? {
        guard isAddressEditable,
              didInteractWithAddress,
              WalletInputValidator.validatedAddress(address) == nil else { return nil }
        return "Enter a valid Ethereum address."
    }

    var secretError: String? {
        guard showsSecretInput,
              didInteractWithSecret,
              derivedAddress == nil else { return nil }
        switch importMethod {
        case .recoveryPhrase:
            return WalletCredentialError.invalidRecoveryPhrase.errorDescription
        case .privateKey:
            return WalletCredentialError.invalidPrivateKey.errorDescription
        case .watchAddress:
            return nil
        }
    }

    var derivedAddress: EVMAddress? {
        try? preparedCredential().address
    }

    var canSubmit: Bool {
        guard !isSubmitting,
              WalletInputValidator.validatedName(name) != nil else { return false }
        switch mode {
        case .edit:
            return true
        case .add where importMethod == .watchAddress:
            return WalletInputValidator.validatedAddress(address) != nil
        case .add:
            return derivedAddress != nil
        }
    }

    func setName(_ value: String) {
        name = WalletInputValidator.limitedName(value)
    }

    func setImportMethod(_ method: WalletImportMethod) {
        guard showsImportMethodPicker, importMethod != method else { return }
        clearSensitiveInput()
        importMethod = method
        didInteractWithAddress = false
        submissionError = nil
    }

    func setSecretInput(_ value: String) {
        guard value != secretInput else { return }
        secretInput = value
        didInteractWithSecret = true
        submissionError = nil
    }

    func credentialImportTarget(
        session: WalletSession
    ) -> WalletCredentialImportTarget? {
        guard let derivedAddress else { return nil }
        return session.credentialImportTarget(for: derivedAddress)
    }

    func reportImportedDuplicate() {
        submissionError = WalletCredentialError
            .credentialAlreadyImported
            .errorDescription
    }

    func submit(session: WalletSession) async -> Bool {
        didInteractWithName = true
        didInteractWithAddress = true
        guard let validName = WalletInputValidator.validatedName(name),
              canSubmit else { return false }
        isSubmitting = true
        submissionError = nil
        defer { isSubmitting = false }
        do {
            switch mode {
            case .add:
                guard importMethod == .watchAddress,
                      let validAddress =
                        WalletInputValidator.validatedAddress(address) else {
                    return false
                }
                try await session.add(
                    name: validName,
                    address: validAddress,
                    cardColor: selectedColor
                )
            case .edit(let wallet):
                try await session.update(
                    id: wallet.id,
                    name: validName,
                    cardColor: selectedColor
                )
            }
            return true
        } catch {
            submissionError = userFacingMessage(
                for: error,
                fallback: "Unable to save wallet."
            )
            return false
        }
    }

    func submitCredential(
        session: WalletSession,
        confirmedUpgradeWalletID: UUID? = nil
    ) async -> Bool {
        didInteractWithName = true
        didInteractWithSecret = true
        guard case .add = mode,
              importMethod != .watchAddress,
              let validName = WalletInputValidator.validatedName(name),
              canSubmit else { return false }

        let prepared: PreparedWalletCredential
        do {
            prepared = try preparedCredential()
        } catch {
            return false
        }

        isSubmitting = true
        submissionError = nil
        defer { isSubmitting = false }
        do {
            try await session.importCredential(
                name: validName,
                prepared: prepared,
                cardColor: selectedColor,
                confirmedUpgradeWalletID: confirmedUpgradeWalletID
            )
            clearSensitiveInput()
            return true
        } catch {
            submissionError = userFacingMessage(
                for: error,
                fallback: "Unable to import wallet."
            )
            return false
        }
    }

    func cancel() {
        clearSensitiveInput()
    }

    func sceneDidBecomeInactive() {
        clearSensitiveInput()
    }

    func clearSensitiveInput() {
        secretInput = ""
        didInteractWithSecret = false
    }

    func delete(session: WalletSession) async -> Bool {
        guard case .edit(let wallet) = mode, !isSubmitting else { return false }
        isSubmitting = true
        submissionError = nil
        defer { isSubmitting = false }
        do {
            try await session.delete(id: wallet.id)
            return true
        } catch {
            submissionError = userFacingMessage(
                for: error,
                fallback: "Unable to delete wallet."
            )
            return false
        }
    }

    private func preparedCredential() throws -> PreparedWalletCredential {
        switch importMethod {
        case .recoveryPhrase:
            try deriver.prepare(.recoveryPhrase(secretInput))
        case .privateKey:
            try deriver.prepare(.privateKey(secretInput))
        case .watchAddress:
            throw WalletCredentialError.invalidPrivateKey
        }
    }

    private func userFacingMessage(
        for error: Error,
        fallback: String
    ) -> String {
        if let error = error as? WalletCredentialError {
            return error.errorDescription ?? fallback
        }
        if let error = error as? WalletSessionError {
            return error.errorDescription ?? fallback
        }
        return fallback
    }
}
