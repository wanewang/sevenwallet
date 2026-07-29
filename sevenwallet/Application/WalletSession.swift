import Foundation
import Observation

nonisolated enum WalletSessionError: LocalizedError, Equatable {
    case mutationInProgress
    case upgradeConfirmationRequired

    var errorDescription: String? {
        switch self {
        case .mutationInProgress:
            "Please wait for the current wallet change to finish."
        case .upgradeConfirmationRequired:
            "Confirm the existing watch-only wallet upgrade to continue."
        }
    }
}

nonisolated struct WalletCredentialRecoveryNotice: Equatable, Identifiable, Sendable {
    let walletID: UUID
    let walletName: String
    let address: EVMAddress

    var id: UUID { walletID }

    var message: String {
        "\(walletName) is now watch only because its protected credential " +
        "is unavailable. Re-import the wallet to restore Imported status."
    }
}

nonisolated enum WalletCredentialImportTarget: Equatable, Sendable {
    case newWallet
    case watchOnlyUpgrade(SavedWallet)
    case importedDuplicate(SavedWallet)
}

@MainActor
@Observable
final class WalletSession {
    private(set) var walletSnapshot = SavedWalletSnapshot(
        wallets: [],
        selectedWalletID: nil
    )
    private(set) var isLoading = false
    private(set) var isDeletingWallet = false
    private(set) var loadErrorMessage: String?
    private(set) var selectionErrorMessage: String?
    private(set) var credentialRecoveryNotice: WalletCredentialRecoveryNotice?
    private var isMutatingWallets = false

    var wallets: [SavedWallet] { walletSnapshot.wallets }
    var selectedWallet: SavedWallet? { walletSnapshot.selectedWallet }

    private let store: any SavedWalletStoreProtocol
    private let cachePurger: any AddressCachePurging
    private let portfolioLoadController: any PortfolioLoadControlling
    private let credentialVault: any WalletCredentialVault

    init(
        store: any SavedWalletStoreProtocol,
        cachePurger: any AddressCachePurging,
        portfolioLoadController: any PortfolioLoadControlling =
            NoopPortfolioLoadController(),
        credentialVault: any WalletCredentialVault =
            KeychainWalletCredentialVault()
    ) {
        self.store = store
        self.cachePurger = cachePurger
        self.portfolioLoadController = portfolioLoadController
        self.credentialVault = credentialVault
    }

    func load() async {
        isLoading = true
        loadErrorMessage = nil
        selectionErrorMessage = nil
        credentialRecoveryNotice = nil
        defer { isLoading = false }
        do {
            let loaded = try await store.loadSnapshot()
            var reconciled = loaded
            var recoveryNotice: WalletCredentialRecoveryNotice?
            for wallet in loaded.wallets {
                guard let reference = wallet.credentialReference else {
                    continue
                }
                switch try await credentialVault.presence(of: reference) {
                case .present:
                    continue
                case .missing:
                    reconciled = try await store.detachCredentialReference(
                        id: wallet.id
                    )
                    if recoveryNotice == nil {
                        recoveryNotice = WalletCredentialRecoveryNotice(
                            walletID: wallet.id,
                            walletName: wallet.name,
                            address: wallet.address
                        )
                    }
                }
            }
            apply(reconciled)
            credentialRecoveryNotice = recoveryNotice
        } catch {
            loadErrorMessage = "Unable to load saved wallets."
        }
    }

    func clearCredentialRecoveryNotice() {
        credentialRecoveryNotice = nil
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

    func importCredential(
        name: String,
        prepared: PreparedWalletCredential,
        cardColor: WalletCardColor,
        confirmedUpgradeWalletID: UUID? = nil
    ) async throws {
        guard !isMutatingWallets else {
            throw WalletSessionError.mutationInProgress
        }
        isMutatingWallets = true
        defer { isMutatingWallets = false }

        let target = credentialImportTarget(for: prepared.address)
        switch target {
        case .importedDuplicate:
            throw WalletCredentialError.credentialAlreadyImported
        case let .watchOnlyUpgrade(wallet):
            guard confirmedUpgradeWalletID == wallet.id else {
                throw WalletSessionError.upgradeConfirmationRequired
            }
        case .newWallet:
            break
        }
        guard await credentialVault.isProtectionAvailable() else {
            throw WalletCredentialError.protectionUnavailable
        }

        switch target {
        case .newWallet:
            try await importNewCredential(
                name: name,
                prepared: prepared,
                cardColor: cardColor
            )
        case let .watchOnlyUpgrade(wallet):
            try await upgradeCredential(
                wallet: wallet,
                prepared: prepared
            )
        case .importedDuplicate:
            break
        }
    }

    func credentialImportTarget(
        for address: EVMAddress
    ) -> WalletCredentialImportTarget {
        let matches = wallets.filter { $0.address == address }
        if let imported = matches.first(where: {
            $0.credentialReference != nil
        }) {
            return .importedDuplicate(imported)
        }
        if let watchOnly = matches.first {
            return .watchOnlyUpgrade(watchOnly)
        }
        return .newWallet
    }

    private func importNewCredential(
        name: String,
        prepared: PreparedWalletCredential,
        cardColor: WalletCardColor
    ) async throws {
        let reference = WalletCredentialReference()
        let wallet = SavedWallet(
            name: name,
            address: prepared.address,
            cardColor: cardColor,
            credentialReference: reference
        )
        let pendingSnapshot = try await store.addAndSelect(wallet)
        do {
            try await credentialVault.store(
                prepared.payload,
                for: reference
            )
        } catch {
            _ = try? await store.rollbackCredentialBackedAdd(id: wallet.id)
            throw error
        }

        await portfolioLoadController.resumePortfolioLoads(
            address: prepared.address
        )
        apply(pendingSnapshot)
    }

    private func upgradeCredential(
        wallet: SavedWallet,
        prepared: PreparedWalletCredential
    ) async throws {
        let reference = WalletCredentialReference()
        _ = try await store.attachCredentialReference(
            id: wallet.id,
            reference: reference
        )
        do {
            try await credentialVault.store(
                prepared.payload,
                for: reference
            )
        } catch {
            _ = try? await store.detachCredentialReference(id: wallet.id)
            throw error
        }

        let completedSnapshot = try await store.select(id: wallet.id)
        await portfolioLoadController.resumePortfolioLoads(
            address: wallet.address
        )
        apply(completedSnapshot)
    }

    func select(id: UUID) async throws {
        guard selectedWallet?.id != id else {
            selectionErrorMessage = nil
            return
        }
        guard !isMutatingWallets else {
            let error = WalletSessionError.mutationInProgress
            selectionErrorMessage = error.errorDescription
            throw error
        }
        isMutatingWallets = true
        defer { isMutatingWallets = false }

        do {
            apply(try await store.select(id: id))
            selectionErrorMessage = nil
        } catch {
            selectionErrorMessage = "Unable to switch wallet."
            throw error
        }
    }

    func clearSelectionError() {
        selectionErrorMessage = nil
    }

    func update(
        id: UUID,
        name: String,
        cardColor: WalletCardColor
    ) async throws {
        guard !isMutatingWallets else {
            throw WalletSessionError.mutationInProgress
        }
        isMutatingWallets = true
        defer { isMutatingWallets = false }

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

        if let reference = wallet.credentialReference {
            try await deleteCredentialBackedWallet(
                wallet,
                reference: reference
            )
            return
        }

        try await deleteWatchOnlyWallet(wallet)
    }

    private func deleteWatchOnlyWallet(_ wallet: SavedWallet) async throws {
        await portfolioLoadController.suspendPortfolioLoads(
            address: wallet.address
        )
        do {
            try await cachePurger.purgeAddressData(address: wallet.address)
            let snapshot = try await store.delete(id: wallet.id)
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

    private func deleteCredentialBackedWallet(
        _ wallet: SavedWallet,
        reference: WalletCredentialReference
    ) async throws {
        do {
            try await credentialVault.delete(for: reference)
        } catch WalletCredentialError.credentialNotFound {
            // The secret is already absent, so deletion can safely continue.
        }

        let watchOnlySnapshot: SavedWalletSnapshot
        do {
            watchOnlySnapshot = try await store.detachCredentialReference(
                id: wallet.id
            )
        } catch {
            apply(snapshotDowngradingCredential(walletID: wallet.id))
            credentialRecoveryNotice = WalletCredentialRecoveryNotice(
                walletID: wallet.id,
                walletName: wallet.name,
                address: wallet.address
            )
            throw error
        }

        await portfolioLoadController.suspendPortfolioLoads(
            address: wallet.address
        )
        do {
            try await cachePurger.purgeAddressData(address: wallet.address)
            let snapshot = try await store.delete(id: wallet.id)
            if snapshot.selectedWallet?.address == wallet.address {
                await portfolioLoadController.resumePortfolioLoads(
                    address: wallet.address
                )
            }
            apply(snapshot)
        } catch {
            apply(watchOnlySnapshot)
            await portfolioLoadController.resumePortfolioLoads(
                address: wallet.address
            )
            throw error
        }
    }

    private func snapshotDowngradingCredential(
        walletID: UUID
    ) -> SavedWalletSnapshot {
        SavedWalletSnapshot(
            wallets: wallets.map { wallet in
                guard wallet.id == walletID else { return wallet }
                return SavedWallet(
                    id: wallet.id,
                    name: wallet.name,
                    address: wallet.address,
                    cardColor: wallet.cardColor,
                    createdAt: wallet.createdAt
                )
            },
            selectedWalletID: walletSnapshot.selectedWalletID
        )
    }

    private func apply(_ snapshot: SavedWalletSnapshot) {
        walletSnapshot = snapshot
    }
}
