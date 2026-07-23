import Foundation
import Observation

nonisolated enum WalletSessionError: LocalizedError, Equatable {
    case mutationInProgress

    var errorDescription: String? {
        "Please wait for the current wallet change to finish."
    }
}

@MainActor
@Observable
final class WalletSession {
    private(set) var wallets: [SavedWallet] = []
    private(set) var selectedWallet: SavedWallet?
    private(set) var isLoading = false
    private(set) var isDeletingWallet = false
    private(set) var loadErrorMessage: String?
    private var isMutatingWallets = false

    private let store: any SavedWalletStoreProtocol
    private let cachePurger: any AddressCachePurging
    private let portfolioLoadController: any PortfolioLoadControlling

    init(
        store: any SavedWalletStoreProtocol,
        cachePurger: any AddressCachePurging,
        portfolioLoadController: any PortfolioLoadControlling =
            NoopPortfolioLoadController()
    ) {
        self.store = store
        self.cachePurger = cachePurger
        self.portfolioLoadController = portfolioLoadController
    }

    func load() async {
        isLoading = true
        loadErrorMessage = nil
        defer { isLoading = false }
        do {
            apply(try await store.loadSnapshot())
        } catch {
            loadErrorMessage = "Unable to load saved wallets."
        }
    }

    func add(
        name: String,
        address: EVMAddress,
        cardColor: WalletCardColor
    ) async throws {
        guard !isMutatingWallets else {
            throw WalletSessionError.mutationInProgress
        }
        isMutatingWallets = true
        defer { isMutatingWallets = false }

        let wallet = SavedWallet(
            name: name,
            address: address,
            cardColor: cardColor
        )
        let snapshot = try await store.addAndSelect(wallet)
        await portfolioLoadController.resumePortfolioLoads(address: address)
        apply(snapshot)
    }

    func update(
        id: UUID,
        name: String,
        cardColor: WalletCardColor
    ) async throws {
        apply(try await store.update(
            id: id,
            name: name,
            cardColor: cardColor
        ))
    }

    func delete(id: UUID) async throws {
        guard !isMutatingWallets else {
            throw WalletSessionError.mutationInProgress
        }
        guard let wallet = wallets.first(where: { $0.id == id }) else {
            throw SavedWalletStoreError.walletNotFound
        }
        isMutatingWallets = true
        isDeletingWallet = true
        defer {
            isDeletingWallet = false
            isMutatingWallets = false
        }

        await portfolioLoadController.suspendPortfolioLoads(
            address: wallet.address
        )
        do {
            try await cachePurger.purgeAddressData(address: wallet.address)
            let snapshot = try await store.delete(id: id)
            if snapshot.selectedWallet?.address == wallet.address {
                await portfolioLoadController.resumePortfolioLoads(
                    address: wallet.address
                )
            }
            apply(snapshot)
        } catch {
            await portfolioLoadController.resumePortfolioLoads(
                address: wallet.address
            )
            throw error
        }
    }

    private func apply(_ snapshot: SavedWalletSnapshot) {
        wallets = snapshot.wallets
        selectedWallet = snapshot.selectedWallet
    }
}
