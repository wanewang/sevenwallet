import SwiftUI

struct WalletTopBar: View {
    let theme: Theme
    let isThemeLight: Bool
    let onToggleTheme: () -> Void

    var body: some View {
        HStack {
            Button(action: {}) {
                HStack(spacing: 4) {
                    Image(systemName: "rectangle.grid.1x2")
                    Image(systemName: "chevron.down")
                        .frame(width: 24, height: 24)
                }
                .font(.system(size: 20, weight: .medium))
                .frame(width: 72, height: 48)
                .background(theme.glass)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
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
                    .background(theme.glass)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(theme.edge, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isThemeLight ? "Light theme" : "Dark theme")
            .accessibilityIdentifier("theme-toggle-button")
        }
        .frame(height: 64)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("wallet-top-bar")
    }
}
