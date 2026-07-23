import SwiftUI

@MainActor
struct WalletRootView: View {
    @State var session: WalletSession
    @State var homeViewModel: WalletHomeViewModel
    @State private var path: [Screen] = []
    @State private var hasResolvedWallets = false

    private var theme: Theme {
        homeViewModel.isThemeLight ? .light : .dark
    }

    var body: some View {
        NavigationStack(path: $path) {
            WalletHomeView(
                viewModel: homeViewModel,
                wallet: session.selectedWallet,
                walletLoadError: session.loadErrorMessage,
                hasResolvedWallets: hasResolvedWallets,
                onRetryWallets: { Task { await loadWallets() } },
                onAddWallet: { path.append(.addWallet) },
                onEditWallet: { path.append(.editWallet($0)) }
            )
            .navigationDestination(for: Screen.self) { screen in
                switch screen {
                case .addWallet:
                    form(mode: .add)
                case .editWallet(let id):
                    if let wallet = session.wallets.first(where: { $0.id == id }) {
                        form(mode: .edit(wallet))
                    } else {
                        Color.clear.task { path.removeAll() }
                    }
                default:
                    Color.clear
                }
            }
        }
        .environment(
            \.colorScheme,
            homeViewModel.isThemeLight ? .light : .dark
        )
        .task { await loadWallets() }
    }

    private func form(mode: WalletFormMode) -> some View {
        WalletFormView(
            mode: mode,
            session: session,
            theme: theme,
            onComplete: { path.removeAll() },
            onCancel: {
                if !path.isEmpty {
                    path.removeLast()
                }
            }
        )
    }

    private func loadWallets() async {
        hasResolvedWallets = false
        await session.load()
        hasResolvedWallets = true
    }
}
