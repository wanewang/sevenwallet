//
//  sevenwalletApp.swift
//  sevenwallet
//
//  Created by Wane on 2026/7/22.
//

import SwiftUI

@main
struct sevenwalletApp: App {
    @State private var state = AppDependencies.makeAppState()

    var body: some Scene {
        WindowGroup {
            WalletRootView(
                session: state.session,
                homeViewModel: state.homeViewModel
            )
        }
    }
}
