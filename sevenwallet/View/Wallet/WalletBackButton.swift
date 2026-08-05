import SwiftUI

struct WalletBackButton: View {
    let theme: Theme
    let isDisabled: Bool
    let accessibilityIdentifier: String
    let action: () -> Void

    init(
        theme: Theme,
        isDisabled: Bool = false,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) {
        self.theme = theme
        self.isDisabled = isDisabled
        self.accessibilityIdentifier = accessibilityIdentifier
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.headline.weight(.semibold))
        }
        .buttonStyle(WalletActionButtonStyle(
            foreground: theme.fg1,
            background: theme.input
        ))
        .disabled(isDisabled)
        .accessibilityLabel("Back")
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
