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
    var didInteractWithName = false
    var didInteractWithAddress = false
    private(set) var isSubmitting = false
    private(set) var submissionError: String?

    init(mode: WalletFormMode) {
        self.mode = mode
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
        if case .add = mode { "Add wallet" } else { "Save changes" }
    }

    var isAddressEditable: Bool {
        if case .add = mode { true } else { false }
    }

    var showsDelete: Bool {
        if case .edit = mode { true } else { false }
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

    var canSubmit: Bool {
        guard !isSubmitting,
              WalletInputValidator.validatedName(name) != nil else { return false }
        return !isAddressEditable ||
            WalletInputValidator.validatedAddress(address) != nil
    }

    func setName(_ value: String) {
        name = WalletInputValidator.limitedName(value)
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
                guard let validAddress =
                    WalletInputValidator.validatedAddress(address) else { return false }
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
            submissionError = "Unable to save wallet."
            return false
        }
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
            submissionError = "Unable to delete wallet."
            return false
        }
    }
}
