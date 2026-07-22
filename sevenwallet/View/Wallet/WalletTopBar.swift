import SwiftUI

struct WalletTopBar: View {
    let theme: Theme
    let isThemeLight: Bool
    let onToggleTheme: () -> Void

    var body: some View {
        HStack {
            Button(action: {}) {
                HStack(spacing: 4) {
                    Image(systemName: "menubar.rectangle")

                    ZStack {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .font(.system(size: 20, weight: .medium))
                .frame(width: 72, height: 48)
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
            .accessibilityLabel("Wallet selector")
            .accessibilityIdentifier("wallet-selector-button")

            Spacer()

            Button(action: onToggleTheme) {
                Image(systemName: isThemeLight ? "sun.max" : "moon")
                    .font(.system(size: 20, weight: .medium))
                    .frame(width: 48, height: 48)
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
            .accessibilityLabel(isThemeLight ? "Switch to dark theme" : "Switch to light theme")
            .accessibilityIdentifier("theme-toggle-button")
        }
        .frame(height: 64)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("wallet-top-bar")
    }
}
