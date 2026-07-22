//
//  WalletHomePage.swift
//  sevenwallet
//
//  Created by Wane on 2026/7/22.
//

import SwiftUI

struct WalletHomeView: View {

    @State private var isThemeLight = false
    private var theme: Theme {
        isThemeLight ? .light : .dark
    }
    @State private var showSelector = false

    var body: some View {
            ZStack(alignment: .top) {
                theme.bg.ignoresSafeArea()
                content
            }
            .toolbar(.hidden, for: .navigationBar)
        .tint(Theme.accent)
        .environment(\.colorScheme, isThemeLight ? .light : .dark)
    }

    // Top bar + scroll body + tab bar (all home-only).
    private var content: some View {
        VStack(spacing: 0) {
        }
    }
}
