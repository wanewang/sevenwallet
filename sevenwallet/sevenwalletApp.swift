//
//  sevenwalletApp.swift
//  sevenwallet
//
//  Created by Wane on 2026/7/22.
//

import SwiftUI

@main
struct sevenwalletApp: App {
    private var tokenSetCopies: Int {
        ProcessInfo.processInfo.arguments.contains("UI_TEST_LONG_TOKEN_LIST")
            ? 4
            : 1
    }

    var body: some Scene {
        WindowGroup {
            WalletHomeView(
                viewModel: .sample(tokenSetCopies: tokenSetCopies)
            )
        }
    }
}
