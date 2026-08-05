import SwiftUI

@MainActor
struct WalletRootView: View {
    @State var session: WalletSession
    @State var homeViewModel: WalletHomeViewModel
    let tokenRepository: any TokenRepositoryProtocol
    @State private var path: [Screen] = []
    @State private var hasResolvedWallets = false

    private var theme: Theme {
        homeViewModel.isThemeLight ? .light : .dark
    }

    var body: some View {
        NavigationStack(path: $path) {
            WalletHomeView(
                viewModel: homeViewModel,
                walletLoadError: session.loadErrorMessage,
                walletSelectionError: session.selectionErrorMessage,
                hasResolvedWallets: hasResolvedWallets,
                isWalletDeletionInProgress: session.isDeletingWallet,
                onRetryWallets: { Task { await loadWallets() } },
                onSelectWallet: { id in
                    Task { try? await session.select(id: id) }
                },
                onShowWalletList: { path.append(.walletList) },
                onAddWallet: { path.append(.addWallet) },
                onEditWallet: { path.append(.editWallet($0)) }
            )
            .onChange(of: session.walletSnapshot, initial: true) { _, snapshot in
                homeViewModel.updateWallets(snapshot)
            }
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
                case .walletList:
                    WalletListView(
                        snapshot: session.walletSnapshot,
                        selectionError: session.selectionErrorMessage,
                        theme: theme,
                        tokenRepository: tokenRepository,
                        onBack: {
                            if path.last == .walletList {
                                path.removeLast()
                            }
                        },
                        onAddWallet: { path.append(.addWallet) },
                        onSelectWallet: { id in
                            do {
                                try await session.select(id: id)
                                path.removeAll()
                            } catch {
                                // The list stays open and renders
                                // session.selectionErrorMessage.
                            }
                        }
                    )
                default:
                    Color.clear
                }
            }
        }
        .environment(
            \.colorScheme,
            homeViewModel.isThemeLight ? .light : .dark
        )
        .onChange(of: path) { oldPath, newPath in
            if oldPath.contains(.walletList), !newPath.contains(.walletList) {
                session.clearSelectionError()
            }
        }
        .alert(
            "Wallet is now watch only",
            isPresented: Binding(
                get: { session.credentialRecoveryNotice != nil },
                set: { isPresented in
                    if !isPresented {
                        session.clearCredentialRecoveryNotice()
                    }
                }
            )
        ) {
            Button("OK") {
                session.clearCredentialRecoveryNotice()
            }
        } message: {
            Text(session.credentialRecoveryNotice?.message ?? "")
        }
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
        homeViewModel.updateWallets(session.walletSnapshot)
        hasResolvedWallets = true
    }
}
