//
//  sevenwalletApp.swift
//  sevenwallet
//
//  Created by Wane on 2026/7/22.
//

import SwiftUI

@main
struct sevenwalletApp: App {
    @State private var homeViewModel = AppDependencies.makeHomeViewModel()

    var body: some Scene {
        WindowGroup {
            WalletHomeView(viewModel: homeViewModel)
        }
    }
}
