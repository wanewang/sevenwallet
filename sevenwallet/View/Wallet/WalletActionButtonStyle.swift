import SwiftUI

struct WalletActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    let foreground: Color
    let background: Color
    let border: Color?

    init(
        foreground: Color,
        background: Color,
        border: Color? = nil
    ) {
        self.foreground = foreground
        self.background = background
        self.border = border
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foreground)
            .frame(width: 44, height: 44)
            .background(background)
            .clipShape(actionShape)
            .overlay {
                if let border {
                    actionShape.stroke(border, lineWidth: 1)
                }
            }
            .contentShape(actionShape)
            .opacity(opacity(isPressed: configuration.isPressed))
    }

    private var actionShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
    }

    private func opacity(isPressed: Bool) -> Double {
        guard isEnabled else { return 0.45 }
        return isPressed ? 0.7 : 1
    }
}
