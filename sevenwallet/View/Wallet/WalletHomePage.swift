import SwiftUI

@MainActor
struct WalletHomeView: View {
    @State private var viewModel: WalletHomeViewModel

    init(viewModel: WalletHomeViewModel? = nil) {
        _viewModel = State(initialValue: viewModel ?? .sample())
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
                            if let walletCard = viewModel.walletCard {
                                WalletCardView(
                                    viewModel: walletCard,
                                    theme: theme
                                )
                            } else {
                                EmptyWalletCardView(theme: theme)
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
        .task {
            await viewModel.loadTokens()
        }
        .toolbar(.hidden, for: .navigationBar)
        .tint(Theme.accent)
        .environment(
            \.colorScheme,
            viewModel.isThemeLight ? .light : .dark
        )
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
