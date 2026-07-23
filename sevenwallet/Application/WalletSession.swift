import Foundation
import Observation

@MainActor
@Observable
final class WalletSession {
    private(set) var wallets: [SavedWallet] = []
    private(set) var selectedWallet: SavedWallet?
    private(set) var isLoading = false
    private(set) var loadErrorMessage: String?

    private let store: any SavedWalletStoreProtocol
    private let cachePurger: any AddressCachePurging

    init(
        store: any SavedWalletStoreProtocol,
        cachePurger: any AddressCachePurging
    ) {
        self.store = store
        self.cachePurger = cachePurger
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
        let wallet = SavedWallet(
            name: name,
            address: address,
            cardColor: cardColor
        )
        apply(try await store.addAndSelect(wallet))
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
        guard let wallet = wallets.first(where: { $0.id == id }) else {
            throw SavedWalletStoreError.walletNotFound
        }
        try await cachePurger.purgeAddressData(address: wallet.address)
        apply(try await store.delete(id: id))
    }

    private func apply(_ snapshot: SavedWalletSnapshot) {
        wallets = snapshot.wallets
        selectedWallet = snapshot.selectedWallet
    }
}
