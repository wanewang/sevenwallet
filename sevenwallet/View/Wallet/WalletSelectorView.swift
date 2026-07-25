import SwiftUI

struct WalletSelectorView: View {
    let theme: Theme
    let snapshot: SavedWalletSnapshot
    let onSelectWallet: (UUID) -> Void
    let onAddWallet: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Button(action: onDismiss) {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss wallet selector")
            .accessibilityIdentifier("wallet-selector-dismiss-button")

            VStack(alignment: .leading, spacing: 2) {
                Text("YOUR WALLETS")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.fg3)
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .padding(.bottom, 6)

                if snapshot.wallets.isEmpty {
                    Text("No wallets yet.")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.fg2)
                        .padding(12)
                } else {
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 2) {
                            ForEach(snapshot.wallets) { savedWallet in
                                walletRow(savedWallet)
                            }
                        }
                    }
                    .scrollIndicators(
                        snapshot.wallets.count > 5 ? .visible : .hidden
                    )
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(height: walletListHeight)
                }

                Divider()
                    .overlay(theme.edge)
                    .padding(.vertical, 8)

                action(
                    icon: "menubar.dock.rectangle",
                    title: "Wallet details",
                    tint: theme.fg1,
                    action: {}
                )
                .accessibilityIdentifier("wallet-details-button")

                action(
                    icon: "plus",
                    title: "Add wallet",
                    tint: Theme.accentHi
                ) {
                    onDismiss()
                    onAddWallet()
                }
                .accessibilityIdentifier("selector-add-wallet-button")
            }
            .padding(8)
            .frame(width: 270)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(theme.bg.opacity(0.96))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(theme.edge)
                    }
            }
            .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
            .padding(.leading, 18)
            .padding(.top, 80)
        }
        .transition(.opacity)
    }

    private var walletListHeight: CGFloat {
        let visibleCount = min(snapshot.wallets.count, 5)
        let rowSpacing = max(visibleCount - 1, 0) * 2
        return CGFloat(visibleCount * 50 + rowSpacing)
    }

    private func walletRow(_ savedWallet: SavedWallet) -> some View {
        let isSelected = savedWallet.id == snapshot.selectedWallet?.id

        return Button {
            onSelectWallet(savedWallet.id)
            onDismiss()
        } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(savedWallet.cardColor.gradient)
                    .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 1) {
                    Text(savedWallet.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.fg1)

                    Text(Fmt.short(savedWallet.address.rawValue))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(theme.fg2)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.accentHi)
                }
            }
            .padding(10)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Theme.accent.opacity(0.12) : .clear)
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityIdentifier("wallet-selector-row-\(savedWallet.id.uuidString)")
    }

    private func action(
        icon: String,
        title: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .frame(height: 42)
        }
        .buttonStyle(.plain)
    }
}
