import SwiftUI

extension WalletCardColor {
    var gradient: LinearGradient {
        let colors: [Color]
        switch self {
        case .blue:
            colors = [Color(hex: 0x3B82F6), Color(hex: 0x252762)]
        case .purple:
            colors = [Color(hex: 0x9B4DFF), Color(hex: 0x50167F)]
        case .pink:
            colors = [Color(hex: 0xE13C99), Color(hex: 0x77105F)]
        case .teal:
            colors = [Color(hex: 0x1AAE9F), Color(hex: 0x075D58)]
        case .amber:
            colors = [Color(hex: 0xF59E0B), Color(hex: 0x854300)]
        }
        return LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
