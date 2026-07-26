import SwiftUI

@MainActor
struct WalletListView: View {
    @State private var viewModel: WalletListViewModel
    @State private var selectingWalletID: UUID?

    let snapshot: SavedWalletSnapshot
    let selectionError: String?
    let theme: Theme
    let onBack: () -> Void
    let onAddWallet: () -> Void
    let onSelectWallet: (UUID) async -> Void

    init(
        snapshot: SavedWalletSnapshot,
        selectionError: String?,
        theme: Theme,
        tokenRepository: any TokenRepositoryProtocol,
        onBack: @escaping () -> Void,
        onAddWallet: @escaping () -> Void,
        onSelectWallet: @escaping (UUID) async -> Void
    ) {
        _viewModel = State(initialValue: WalletListViewModel(
            tokenRepository: tokenRepository
        ))
        self.snapshot = snapshot
        self.selectionError = selectionError
        self.theme = theme
        self.onBack = onBack
        self.onAddWallet = onAddWallet
        self.onSelectWallet = onSelectWallet
    }

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()

            VStack(spacing: 18) {
                header
                    .padding(.horizontal, 18)

                ScrollView {
                    LazyVStack(spacing: 16) {
                        if let selectionError {
                            errorMessage(
                                selectionError,
                                identifier: "wallet-list-selection-error"
                            )
                        }

                        if viewModel.hasPortfolioFailures {
                            portfolioError
                        }

                        if viewModel.rows.isEmpty {
                            emptyState
                        } else {
                            ForEach(viewModel.rows) { row in
                                walletRow(row)
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 18)
                }
                .scrollIndicators(.hidden)
            }
            .padding(.top, 18)
        }
        .toolbar(.hidden, for: .navigationBar)
        .tint(Theme.accent)
        .onAppear { viewModel.update(snapshot: snapshot) }
        .onChange(of: snapshot) { _, newSnapshot in
            viewModel.update(snapshot: newSnapshot)
        }
        .onDisappear { viewModel.cancel() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(theme.fg1)
                    .frame(width: 44, height: 44)
                    .background(theme.input)
                    .clipShape(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            .accessibilityIdentifier("wallet-list-back-button")

            Text("Wallets")
                .font(.title2.bold())
                .foregroundStyle(theme.fg1)
                .accessibilityIdentifier("wallet-list-title")

            Spacer()

            Button(action: onAddWallet) {
                Image(systemName: "plus")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.accentHi)
                    .frame(width: 44, height: 44)
                    .background(Theme.accent.opacity(0.14))
                    .clipShape(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Theme.accent.opacity(0.4), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add wallet")
            .accessibilityIdentifier("wallet-list-add-button")
        }
    }

    private var emptyState: some View {
        Text("No wallets yet.\nTap + to add one.")
            .font(.subheadline)
            .foregroundStyle(theme.fg2)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 44)
            .accessibilityIdentifier("wallet-list-empty-state")
    }

    private var portfolioError: some View {
        HStack(spacing: 12) {
            Label(
                "Some wallet balances couldn’t be loaded.",
                systemImage: "exclamationmark.circle"
            )
            .font(.caption)
            .foregroundStyle(Theme.warn)

            Spacer(minLength: 8)

            Button("Retry") {
                Task { await viewModel.retryFailed() }
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)
            .accessibilityIdentifier("wallet-list-retry-button")
        }
        .padding(12)
        .background(theme.input)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("wallet-list-portfolio-error")
    }

    private func errorMessage(
        _ message: String,
        identifier: String
    ) -> some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(.caption)
            .foregroundStyle(Theme.warn)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(theme.input)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityIdentifier(identifier)
    }

    private func walletRow(_ row: WalletListRowViewModel) -> some View {
        let isActive = row.id == viewModel.selectedWalletID

        return Button {
            guard selectingWalletID == nil else { return }
            selectingWalletID = row.id
            Task {
                await onSelectWallet(row.id)
                selectingWalletID = nil
            }
        } label: {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(row.wallet.cardColor.gradient)
                    .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(row.wallet.name)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(theme.fg1)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        if isActive {
                            Text("Active")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Theme.accentHi)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Theme.accent.opacity(0.18))
                                .clipShape(Capsule())
                        }
                    }

                    Text(row.shortenedAddress)
                        .font(.caption.monospaced())
                        .foregroundStyle(theme.fg2)
                        .lineLimit(1)

                    Text("Ethereum")
                        .font(.caption)
                        .foregroundStyle(theme.fg2)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(row.formattedTotalValue)
                        .font(.headline.monospaced())
                        .foregroundStyle(theme.fg1)

                    Text(row.formattedAssetCount)
                        .font(.caption)
                        .foregroundStyle(theme.fg3)
                }
                .layoutPriority(1)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
            .background(theme.glass)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(
                        isActive ? Theme.accent.opacity(0.6) : theme.edge,
                        lineWidth: isActive ? 1.5 : 1
                    )
            }
            .shadow(
                color: isActive ? Theme.accent.opacity(0.12) : .clear,
                radius: 18
            )
            .contentShape(RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            ))
        }
        .buttonStyle(.plain)
        .disabled(selectingWalletID != nil)
        .accessibilityLabel(accessibilityLabel(for: row, isActive: isActive))
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityIdentifier("wallet-list-row-\(row.id.uuidString)")
    }

    private func accessibilityLabel(
        for row: WalletListRowViewModel,
        isActive: Bool
    ) -> String {
        [
            row.wallet.name,
            isActive ? "Active" : nil,
            row.shortenedAddress,
            "Ethereum",
            row.formattedTotalValue,
            row.formattedAssetCount
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }
}
