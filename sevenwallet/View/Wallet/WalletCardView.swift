import SwiftUI
import UIKit

struct WalletCardView: View {
    let viewModel: WalletCardViewModel
    let theme: Theme
    let onEdit: () -> Void

    @State private var didCopy = false
    @State private var copyResetTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Button(action: onEdit) {
                    HStack(spacing: 8) {
                        Text(viewModel.name)
                            .font(.headline)
                        Image(systemName: "pencil")
                            .font(.caption.weight(.semibold))
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.white)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit \(viewModel.name)")
                .accessibilityIdentifier("edit-wallet-button")

                Button(action: copyAddress) {
                    HStack(spacing: 6) {
                        Text(viewModel.shortenedAddress)
                            .font(.caption.monospaced())
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white.opacity(didCopy ? 1 : 0.75))
                            .frame(width: 20, height: 20)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(didCopy ? "Wallet address copied" : "Copy wallet address")
                .accessibilityIdentifier("copy-wallet-address-button")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("TOTAL VALUE")
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.7))

                Text(viewModel.formattedTotalValue)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .padding(16)
        .frame(
            maxWidth: .infinity,
            minHeight: Theme.walletCardMinimumHeight,
            alignment: .leading
        )
        .background(viewModel.cardColor.gradient)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("wallet-card")
    }

    private func copyAddress() {
        UIPasteboard.general.string = viewModel.address
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation { didCopy = true }
        copyResetTask?.cancel()
        copyResetTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            withAnimation { didCopy = false }
        }
    }
}
