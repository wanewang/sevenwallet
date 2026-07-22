import SwiftUI

struct EmptyWalletCardView: View {
    let theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SEVEN WALLET")
                .font(.subheadline.weight(.medium))
                .tracking(2.4)
                .foregroundStyle(theme.fg3)

            Spacer()

            VStack(spacing: 22) {
                Image(systemName: "plus")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(Theme.accentHi)
                    .frame(width: 56, height: 56)
                    .background(Theme.accent.opacity(0.10), in: Circle())
                    .overlay {
                        Circle()
                            .stroke(Theme.accent.opacity(0.55), lineWidth: 1)
                    }
                    .shadow(color: Theme.accent.opacity(0.40), radius: 12)

                VStack(spacing: 6) {
                    Text("Add your first wallet")
                        .font(.title2.bold())
                        .foregroundStyle(theme.fg1)

                    Text("Import an address to start tracking")
                        .font(.subheadline)
                        .foregroundStyle(theme.fg2)
                }
                .frame(maxWidth: .infinity)
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: Theme.walletCardMinimumHeight)
        .background(theme.glass)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(
                    theme.edge,
                    style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("empty-wallet-card")
    }
}
