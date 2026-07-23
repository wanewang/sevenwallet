import SwiftUI

@MainActor
struct WalletFormView: View {
    @State private var viewModel: WalletFormViewModel
    let session: WalletSession
    let theme: Theme
    let onComplete: () -> Void
    let onCancel: () -> Void
    @State private var confirmsDelete = false

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

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    preview
                    walletNameField
                    addressField
                    networkRow
                    colorPicker
                    primaryAction

                    if viewModel.showsDelete {
                        deleteButton
                    }
                }
                .padding(18)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        .tint(Theme.accent)
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
            Text("This removes the wallet and its cached address data from this device.")
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Button(action: onCancel) {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(theme.fg1)
                    .frame(width: 44, height: 44)
                    .background(theme.input)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

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

    private var walletNameField: some View {
        formSection(title: "Wallet name", error: viewModel.nameError) {
            TextField(
                "Main Wallet",
                text: Binding(
                    get: { viewModel.name },
                    set: {
                        viewModel.didInteractWithName = true
                        viewModel.setName($0)
                    }
                )
            )
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
                            viewModel.didInteractWithAddress = true
                            viewModel.address = $0
                        }
                    )
                )
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
                }
            }
        }
    }

    private var primaryAction: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error = viewModel.submissionError {
                inlineError(error)
            }

            Button {
                Task {
                    if await viewModel.submit(session: session) {
                        onComplete()
                    }
                }
            } label: {
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

            if let error {
                inlineError(error)
            }
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
        let trimmed = viewModel.address.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "0x…" : Fmt.short(trimmed)
    }
}
