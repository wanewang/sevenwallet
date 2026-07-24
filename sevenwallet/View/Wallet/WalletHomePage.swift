import SwiftUI

@MainActor
struct WalletHomeView: View {
    @State private var viewModel: WalletHomeViewModel
    let wallet: SavedWallet?
    let walletLoadError: String?
    let hasResolvedWallets: Bool
    let isWalletDeletionInProgress: Bool
    let onRetryWallets: () -> Void
    let onAddWallet: () -> Void
    let onEditWallet: (UUID) -> Void

    init(
        viewModel: WalletHomeViewModel? = nil,
        wallet: SavedWallet? = nil,
        walletLoadError: String? = nil,
        hasResolvedWallets: Bool = true,
        isWalletDeletionInProgress: Bool = false,
        onRetryWallets: @escaping () -> Void = {},
        onAddWallet: @escaping () -> Void = {},
        onEditWallet: @escaping (UUID) -> Void = { _ in }
    ) {
        _viewModel = State(initialValue: viewModel ?? .sample())
        self.wallet = wallet
        self.walletLoadError = walletLoadError
        self.hasResolvedWallets = hasResolvedWallets
        self.isWalletDeletionInProgress = isWalletDeletionInProgress
        self.onRetryWallets = onRetryWallets
        self.onAddWallet = onAddWallet
        self.onEditWallet = onEditWallet
    }

    private var theme: Theme {
        viewModel.isThemeLight ? .light : .dark
    }

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                WalletTopBar(
                    theme: theme,
                    isThemeLight: viewModel.isThemeLight,
                    onToggleTheme: viewModel.toggleTheme
                )

                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section {
                            if let walletLoadError {
                                walletStorageError(walletLoadError)
                                    .padding(.bottom, 12)
                            }

                            if let walletCard = viewModel.walletCard {
                                WalletCardView(
                                    viewModel: walletCard,
                                    onEdit: { onEditWallet(walletCard.id) }
                                )
                            } else if hasResolvedWallets,
                                      wallet == nil,
                                      walletLoadError == nil {
                                EmptyWalletCardView(
                                    theme: theme,
                                    onAdd: onAddWallet
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 24)

                        Section {
                            if let error = viewModel.tokenErrorMessage,
                               viewModel.tokens.isEmpty {
                                initialTokenError(error)
                            } else {
                                if let error = viewModel.tokenErrorMessage {
                                    compactTokenError(error)
                                }

                                ForEach(
                                    Array(viewModel.tokens.enumerated()),
                                    id: \.element.id
                                ) { index, token in
                                    TokenRowView(
                                        viewModel: token,
                                        theme: theme,
                                        isFirst: index == 0,
                                        isLast: index == viewModel.tokens.count - 1
                                    )
                                    .padding(.horizontal, 16)
                                }
                            }
                        } header: {
                            tokensHeader
                        }
                    }
                    .padding(.bottom, 16)
                }
                .refreshable {
                    await viewModel.refreshTokens()
                }
            }
        }
        .onChange(of: wallet, initial: true) { _, wallet in
            viewModel.updateWallet(wallet)
        }
        .onChange(of: walletLoadKey.canLoad, initial: true) { _, canLoad in
            viewModel.updateLoadingEligibility(canLoad)
        }
        .task(id: walletLoadKey) {
            viewModel.updateLoadingEligibility(walletLoadKey.canLoad)
            guard walletLoadKey.canLoad else { return }
            viewModel.updateWallet(wallet)
            await viewModel.loadSelectedResource()
        }
        .toolbar(.hidden, for: .navigationBar)
        .tint(Theme.accent)
        .environment(
            \.colorScheme,
            viewModel.isThemeLight ? .light : .dark
        )
    }

    private var walletLoadKey: WalletLoadKey {
        WalletLoadKey(
            canLoad: hasResolvedWallets
                && walletLoadError == nil
                && !isWalletDeletionInProgress,
            address: wallet?.address
        )
    }

    private func walletStorageError(_ message: String) -> some View {
        HStack(spacing: 12) {
            Label(message, systemImage: "exclamationmark.circle")
                .font(.caption)
                .foregroundStyle(Theme.warn)

            Spacer(minLength: 8)

            Button("Retry", action: onRetryWallets)
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .accessibilityIdentifier("retry-wallets-button")
        }
        .accessibilityIdentifier("wallet-load-error-message")
    }

    private var tokensHeader: some View {
        HStack {
            Text("Tokens")
                .font(.title2.bold())
                .foregroundStyle(theme.fg1)

            if viewModel.isLoadingTokens {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Loading tokens")
                    .accessibilityIdentifier("tokens-loading-indicator")
            }

            Spacer()

            Button(action: {}) {
                Label("Manage", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .background(theme.chip)
                    .clipShape(
                        RoundedRectangle(cornerRadius: Theme.chipCorner, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.chipCorner, style: .continuous)
                            .stroke(theme.edge, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("manage-tokens-button")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(theme.bg)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tokens-header")
    }

    private func initialTokenError(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(theme.fg2)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("token-error-message")

            Button("Retry") {
                Task { await viewModel.retryTokens() }
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("retry-tokens-button")
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
    }

    private func compactTokenError(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(.caption)
            .foregroundStyle(Theme.warn)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .accessibilityIdentifier("token-error-message")
    }
}

private struct WalletLoadKey: Hashable {
    let canLoad: Bool
    let address: EVMAddress?
}
