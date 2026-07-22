import SwiftUI
import UIKit

struct WalletCardView: View {
    let viewModel: WalletCardViewModel
    let theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Text(viewModel.name)
                    .font(.headline)
                    .foregroundStyle(theme.fg1)

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    Text(viewModel.shortenedAddress)
                        .font(.caption.monospaced())
                        .foregroundStyle(theme.fg2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Button {
                        UIPasteboard.general.string = viewModel.address
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Copy wallet address")
                    .accessibilityIdentifier("copy-wallet-address-button")
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("TOTAL VALUE")
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(theme.fg2)

                Text(viewModel.formattedTotalValue)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.fg1)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.glass)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(theme.edge, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("wallet-card")
    }
}
