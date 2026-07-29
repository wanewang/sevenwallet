import SwiftUI

@MainActor
struct WalletFormView: View {
    private enum FocusedField {
        case name
        case address
        case secret
    }

    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: WalletFormViewModel
    let session: WalletSession
    let theme: Theme
    let onComplete: () -> Void
    let onCancel: () -> Void
    @State private var confirmsDelete = false
    @State private var credentialConfirmation: WalletCredentialImportTarget?
    @FocusState private var focusedField: FocusedField?

    init(
        mode: WalletFormMode,
        session: WalletSession,
        theme: Theme,
        onComplete: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: WalletFormViewModel(mode: mode))
        self.session = session
        self.theme = theme
        self.onComplete = onComplete
        self.onCancel = onCancel
    }

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()

            VStack(spacing: 22) {
                header
                    .padding(.horizontal, 18)

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        preview

                        if viewModel.showsImportMethodPicker {
                            importMethodPicker
                        }

                        walletNameField

                        if viewModel.showsSecretInput {
                            secretField
                            if let address = viewModel.derivedAddress {
                                derivedAddress(address)
                            }
                        } else {
                            addressField
                        }

                        if let ownershipTitle = viewModel.ownershipTitle {
                            ownershipRow(ownershipTitle)
                        }

                        networkRow
                        colorPicker
                        primaryAction

                        if viewModel.showsDelete {
                            deleteButton
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 18)
                    .contentShape(Rectangle())
                    .onTapGesture { focusedField = nil }
                }
                .scrollDismissesKeyboard(.immediately)
                .scrollIndicators(.hidden)
            }
            .padding(.top, 18)
        }
        .toolbar(.hidden, for: .navigationBar)
        .tint(Theme.accent)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                viewModel.sceneDidBecomeInactive()
            }
        }
        .onDisappear { viewModel.cancel() }
        .alert(
            credentialConfirmationTitle,
            isPresented: Binding(
                get: { credentialConfirmation != nil },
                set: { isPresented in
                    if !isPresented { credentialConfirmation = nil }
                }
            )
        ) {
            Button(credentialConfirmationActionTitle) {
                confirmCredentialImport()
            }
            Button("Cancel", role: .cancel) {
                credentialConfirmation = nil
                viewModel.cancel()
            }
        } message: {
            Text(credentialConfirmationMessage)
        }
        .confirmationDialog(
            "Delete wallet?",
            isPresented: $confirmsDelete,
            titleVisibility: .visible
        ) {
            Button("Delete wallet", role: .destructive) {
                Task {
                    if await viewModel.delete(session: session) {
                        onComplete()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteConfirmationMessage)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            WalletBackButton(
                theme: theme,
                isDisabled: viewModel.isSubmitting,
                accessibilityIdentifier: "wallet-form-back-button"
            ) {
                viewModel.cancel()
                onCancel()
            }

            Text(viewModel.title)
                .font(.title2.bold())
                .foregroundStyle(theme.fg1)

            Spacer()
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(previewName)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)

            Spacer(minLength: 12)

            HStack(alignment: .bottom) {
                Text("ETHEREUM")
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.72))

                Spacer()

                Text(previewAddress)
                    .font(.caption.monospaced())
                    .foregroundStyle(.white.opacity(0.82))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
        .background(viewModel.selectedColor.gradient)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        }
    }

    private var importMethodPicker: some View {
        formSection(title: "Import method", error: nil) {
            Picker(
                "Import method",
                selection: Binding(
                    get: { viewModel.importMethod },
                    set: { viewModel.setImportMethod($0) }
                )
            ) {
                ForEach(WalletImportMethod.allCases) { method in
                    Text(importMethodTitle(method)).tag(method)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("wallet-import-method-picker")
        }
    }

    private var walletNameField: some View {
        formSection(title: "Wallet name", error: viewModel.nameError) {
            TextField(
                "Main Wallet",
                text: Binding(
                    get: { viewModel.name },
                    set: {
                        if $0 != viewModel.name {
                            viewModel.didInteractWithName = true
                        }
                        viewModel.setName($0)
                    }
                )
            )
            .focused($focusedField, equals: .name)
            .textInputAutocapitalization(.words)
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .background(theme.input)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(theme.fg1)
            .accessibilityIdentifier("wallet-name-field")
        }
    }

    @ViewBuilder
    private var addressField: some View {
        formSection(title: "Wallet address", error: viewModel.addressError) {
            if viewModel.isAddressEditable {
                TextField(
                    "0x…",
                    text: Binding(
                        get: { viewModel.address },
                        set: {
                            if $0 != viewModel.address {
                                viewModel.didInteractWithAddress = true
                            }
                            viewModel.address = $0
                        }
                    )
                )
                .focused($focusedField, equals: .address)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body.monospaced())
                .padding(.horizontal, 14)
                .frame(minHeight: 52)
                .background(theme.input)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(theme.fg1)
                .accessibilityIdentifier("wallet-address-field")
            } else {
                Text(viewModel.address)
                    .font(.callout.monospaced())
                    .foregroundStyle(theme.fg2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    .padding(.horizontal, 14)
                    .background(theme.input)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityIdentifier("wallet-address-field")
            }
        }
    }

    private var secretField: some View {
        formSection(
            title: viewModel.importMethod == .recoveryPhrase
                ? "Recovery phrase"
                : "Private key",
            error: viewModel.secretError
        ) {
            SecureField(
                viewModel.importMethod == .recoveryPhrase
                    ? "12 or 24 English words"
                    : "64 hexadecimal characters",
                text: Binding(
                    get: { viewModel.secretInput },
                    set: { viewModel.setSecretInput($0) }
                )
            )
            .focused($focusedField, equals: .secret)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.body.monospaced())
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .background(theme.input)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(theme.fg1)
            .privacySensitive()
            .accessibilityIdentifier(
                viewModel.importMethod == .recoveryPhrase
                    ? "wallet-recovery-phrase-field"
                    : "wallet-private-key-field"
            )
        }
    }

    private func derivedAddress(_ address: EVMAddress) -> some View {
        formSection(title: "Derived address", error: nil) {
            Text(Fmt.short(address.rawValue))
                .font(.callout.monospaced())
                .foregroundStyle(theme.fg2)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .padding(.horizontal, 14)
                .background(theme.input)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityLabel("Derived Ethereum address")
                .accessibilityValue(address.rawValue)
                .accessibilityIdentifier("wallet-derived-address")
        }
    }

    private func ownershipRow(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ownership")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.fg1)

            Label(
                title,
                systemImage: title == "Imported" ? "key.fill" : "eye.fill"
            )
            .font(.body.weight(.medium))
            .foregroundStyle(theme.fg1)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .padding(.horizontal, 14)
            .background(theme.input)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityIdentifier("wallet-ownership-status")
        }
    }

    private var networkRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Network")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.fg1)

            HStack(spacing: 12) {
                Image(systemName: "network")
                    .foregroundStyle(Theme.accentHi)
                Text("Ethereum")
                    .font(.body.weight(.medium))
                    .foregroundStyle(theme.fg1)
                Spacer()
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(theme.fg3)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .background(theme.input)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text("Ethereum is the only supported network for this wallet.")
                .font(.caption)
                .foregroundStyle(theme.fg2)
        }
    }

    private var colorPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Card color")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.fg1)

            HStack(spacing: 12) {
                ForEach(WalletCardColor.allCases) { color in
                    Button {
                        viewModel.selectedColor = color
                    } label: {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(color.gradient)
                            .frame(width: 42, height: 42)
                            .padding(3)
                            .overlay {
                                RoundedRectangle(
                                    cornerRadius: 14,
                                    style: .continuous
                                )
                                .stroke(
                                    viewModel.selectedColor == color
                                        ? Theme.accentHi
                                        : .clear,
                                    lineWidth: 3
                                )
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(color.rawValue.capitalized) card color")
                    .accessibilityIdentifier("wallet-color-\(color.rawValue)")
                    .accessibilityAddTraits(
                        viewModel.selectedColor == color ? .isSelected : []
                    )
                }
            }
        }
    }

    private var primaryAction: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error = viewModel.submissionError {
                inlineError(error)
                    .accessibilityIdentifier("wallet-submission-error")
            }

            Button(action: performPrimaryAction) {
                if viewModel.isSubmitting {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                } else {
                    Text(viewModel.primaryActionTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
            }
            .foregroundStyle(.white)
            .frame(minHeight: 52)
            .background(
                viewModel.canSubmit
                    ? Theme.accent
                    : Theme.accent.opacity(0.35)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .buttonStyle(.plain)
            .disabled(!viewModel.canSubmit)
            .accessibilityIdentifier("wallet-primary-action")
        }
    }

    private var deleteButton: some View {
        Button {
            confirmsDelete = true
        } label: {
            Text("Delete wallet")
                .font(.headline)
                .foregroundStyle(Theme.neg)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Theme.neg, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isSubmitting)
        .accessibilityIdentifier("delete-wallet-button")
    }

    private func performPrimaryAction() {
        guard viewModel.showsSecretInput else {
            Task {
                if await viewModel.submit(session: session) {
                    onComplete()
                }
            }
            return
        }

        switch viewModel.credentialImportTarget(session: session) {
        case .importedDuplicate:
            viewModel.reportImportedDuplicate()
        case .newWallet, .watchOnlyUpgrade:
            credentialConfirmation = viewModel.credentialImportTarget(
                session: session
            )
        case nil:
            break
        }
    }

    private func confirmCredentialImport() {
        let upgradeID: UUID?
        if case let .watchOnlyUpgrade(wallet) = credentialConfirmation {
            upgradeID = wallet.id
        } else {
            upgradeID = nil
        }
        credentialConfirmation = nil
        Task {
            if await viewModel.submitCredential(
                session: session,
                confirmedUpgradeWalletID: upgradeID
            ) {
                onComplete()
            }
        }
    }

    private var credentialConfirmationTitle: String {
        if case .watchOnlyUpgrade = credentialConfirmation {
            return "Upgrade wallet?"
        }
        return "Import wallet?"
    }

    private var credentialConfirmationActionTitle: String {
        if case .watchOnlyUpgrade = credentialConfirmation {
            return "Upgrade wallet"
        }
        return "Import wallet"
    }

    private var credentialConfirmationMessage: String {
        let warning = "This app does not back up, reveal, or export your " +
            "wallet credential. Keep your own secure backup."
        if case let .watchOnlyUpgrade(wallet) = credentialConfirmation {
            return "\(wallet.name) (\(wallet.address.rawValue)) will be " +
                "upgraded in place. \(warning)"
        }
        return warning
    }

    private var deleteConfirmationMessage: String {
        guard case let .edit(wallet) = viewModel.mode,
              wallet.credentialReference != nil else {
            return "This removes the wallet and its cached address data from this device."
        }
        return "This permanently removes the protected credential, wallet, " +
            "and cached address data from this device. Authentication is required."
    }

    private func formSection<Content: View>(
        title: String,
        error: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.fg1)
            content()
            if let error { inlineError(error) }
        }
    }

    private func inlineError(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(.caption)
            .foregroundStyle(Theme.neg)
    }

    private var previewName: String {
        let trimmed = viewModel.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "WALLET NAME" : trimmed.uppercased()
    }

    private var previewAddress: String {
        if let derivedAddress = viewModel.derivedAddress {
            return Fmt.short(derivedAddress.rawValue)
        }
        let trimmed = viewModel.address.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "0x…" : Fmt.short(trimmed)
    }

    private func importMethodTitle(_ method: WalletImportMethod) -> String {
        switch method {
        case .watchAddress:
            "Watch address"
        case .recoveryPhrase:
            "Recovery phrase"
        case .privateKey:
            "Private key"
        }
    }
}
