//
//  Theme.swift
//  System · Seven color palette, resolved per light/dark.
//

import SwiftUI

struct Theme {
    static let chipCorner: CGFloat = 14
    static let walletCardMinimumHeight: CGFloat = 208

    let bg: Color
    let fg1: Color          // primary text
    let fg2: Color          // secondary
    let fg3: Color          // tertiary / disabled
    let glass: Color        // raised glass fill
    let edge: Color         // hairline border
    let input: Color        // input / raised row
    let chip: Color         // pill background
    let divider: Color

    static let accent   = Color(hex: 0x3B82F6)
    static let accentHi = Color(hex: 0x60A5FA)
    static let pos      = Color(hex: 0x22C55E)
    static let neg      = Color(hex: 0xEF4444)
    static let warn     = Color(hex: 0xF59E0B)

    static let dark = Theme(
        bg: Color(hex: 0x0A0A0C),
        fg1: Color(hex: 0xF5F7FA),
        fg2: Color(hex: 0x9DA3AE),
        fg3: Color(hex: 0x5B6171),
        glass: Color.white.opacity(0.04),
        edge: Color.white.opacity(0.08),
        input: Color(hex: 0x1F2229),
        chip: Color.white.opacity(0.05),
        divider: Color.white.opacity(0.05)
    )

    static let light = Theme(
        bg: Color(hex: 0xECEEF3),
        fg1: Color(hex: 0x161A22),
        fg2: Color(hex: 0x5C6474),
        fg3: Color(hex: 0x9AA1B0),
        glass: Color.black.opacity(0.035),
        edge: Color.black.opacity(0.09),
        input: Color.white,
        chip: Color.black.opacity(0.05),
        divider: Color.black.opacity(0.06)
    )
}
