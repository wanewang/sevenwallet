import Foundation
import Observation

@MainActor
struct WalletListRowViewModel: Identifiable, Equatable {
    let wallet: SavedWallet
    var totalValue: Decimal?
    var assetCount: Int?
    var isLoading: Bool
    var hasFailed: Bool

    var id: UUID { wallet.id }

    var shortenedAddress: String {
        Fmt.short(wallet.address.rawValue)
    }

    var ownershipTitle: String {
        wallet.credentialReference == nil ? "Watch only" : "Imported"
    }

    var formattedTotalValue: String {
        if let totalValue {
            return Fmt.usd(totalValue)
        }
        return isLoading ? "—" : "Unavailable"
    }

    var formattedAssetCount: String {
        guard let assetCount else {
            return isLoading ? "Loading" : "Unavailable"
        }
        return "\(assetCount) \(assetCount == 1 ? "asset" : "assets")"
    }
}

@MainActor
@Observable
final class WalletListViewModel {
    private(set) var rows: [WalletListRowViewModel] = []
    private(set) var selectedWalletID: UUID?

    var hasPortfolioFailures: Bool {
        rows.contains { $0.hasFailed }
    }

    private let tokenRepository: any TokenRepositoryProtocol
    private var portfolioTasks: [UUID: Task<Void, Never>] = [:]
    private var generations: [UUID: Int] = [:]

    init(tokenRepository: any TokenRepositoryProtocol) {
        self.tokenRepository = tokenRepository
    }

    func load(snapshot: SavedWalletSnapshot) async {
        update(snapshot: snapshot)
        let tasks = snapshot.wallets.compactMap { portfolioTasks[$0.id] }
        for task in tasks {
            await task.value
        }
    }

    func update(snapshot: SavedWalletSnapshot) {
        let walletsByID = Dictionary(
            uniqueKeysWithValues: snapshot.wallets.map { ($0.id, $0) }
        )
        for row in rows {
            if walletsByID[row.id]?.address != row.wallet.address {
                invalidateRequest(for: row.id)
            }
        }

        let existingRows = Dictionary(
            uniqueKeysWithValues: rows.map { ($0.id, $0) }
        )
        rows = snapshot.wallets.map { wallet in
            guard let row = existingRows[wallet.id],
                  row.wallet.address == wallet.address else {
                return WalletListRowViewModel(
                    wallet: wallet,
                    totalValue: nil,
                    assetCount: nil,
                    isLoading: false,
                    hasFailed: false
                )
            }
            return WalletListRowViewModel(
                wallet: wallet,
                totalValue: row.totalValue,
                assetCount: row.assetCount,
                isLoading: row.isLoading,
                hasFailed: row.hasFailed
            )
        }
        selectedWalletID = snapshot.selectedWalletID

        for row in rows where shouldStartInitialLoad(row) {
            startPortfolioLoad(for: row.id)
        }
    }

    func retryFailed() async {
        let failedIDs = rows.compactMap { $0.hasFailed ? $0.id : nil }
        for id in failedIDs {
            startPortfolioLoad(for: id)
        }
        let tasks = failedIDs.compactMap { portfolioTasks[$0] }
        for task in tasks {
            await task.value
        }
    }

    func cancel() {
        for id in portfolioTasks.keys {
            generations[id, default: 0] += 1
        }
        let tasks = portfolioTasks.values
        portfolioTasks.removeAll()
        tasks.forEach { $0.cancel() }
        for index in rows.indices {
            rows[index].isLoading = false
        }
    }

    private func shouldStartInitialLoad(_ row: WalletListRowViewModel) -> Bool {
        portfolioTasks[row.id] == nil
            && row.totalValue == nil
            && !row.hasFailed
            && !row.isLoading
    }

    private func startPortfolioLoad(for id: UUID) {
        guard portfolioTasks[id] == nil,
              let row = rows.first(where: { $0.id == id }) else { return }

        generations[id, default: 0] += 1
        let generation = generations[id, default: 0]
        let address = row.wallet.address
        updateRow(id: id) {
            $0.isLoading = true
            $0.hasFailed = false
        }
        portfolioTasks[id] = Task { [weak self] in
            guard let self else { return }
            await self.consumePortfolio(
                walletID: id,
                address: address,
                generation: generation
            )
        }
    }

    private func consumePortfolio(
        walletID: UUID,
        address: EVMAddress,
        generation: Int
    ) async {
        var receivedPortfolio = false
        do {
            let stream = tokenRepository.portfolio(
                address: address,
                policy: .ifExpired
            )
            for try await event in stream {
                try Task.checkCancellation()
                guard isCurrent(
                    walletID: walletID,
                    address: address,
                    generation: generation
                ) else { return }

                switch event {
                case .cached(let portfolio), .fresh(let portfolio):
                    receivedPortfolio = true
                    apply(
                        portfolio: portfolio,
                        walletID: walletID
                    )
                case .refreshing:
                    updateRow(id: walletID) { $0.isLoading = true }
                }
            }

            guard isCurrent(
                walletID: walletID,
                address: address,
                generation: generation
            ) else { return }
            updateRow(id: walletID) {
                $0.isLoading = false
                if !receivedPortfolio, $0.totalValue == nil {
                    $0.hasFailed = true
                }
            }
        } catch is CancellationError {
            guard isCurrent(
                walletID: walletID,
                address: address,
                generation: generation
            ) else { return }
            updateRow(id: walletID) { $0.isLoading = false }
        } catch {
            guard isCurrent(
                walletID: walletID,
                address: address,
                generation: generation
            ) else { return }
            updateRow(id: walletID) {
                $0.isLoading = false
                $0.hasFailed = true
            }
        }

        if isCurrent(
            walletID: walletID,
            address: address,
            generation: generation
        ) {
            portfolioTasks[walletID] = nil
        }
    }

    private func apply(
        portfolio: TokenPortfolio,
        walletID: UUID
    ) {
        let total = portfolio.tokens.reduce(Decimal.zero) { result, token in
            result + token.balance * (token.marketPriceUSD ?? 0)
        }
        updateRow(id: walletID) {
            $0.totalValue = total
            $0.assetCount = portfolio.tokens.count
            $0.hasFailed = false
        }
    }

    private func isCurrent(
        walletID: UUID,
        address: EVMAddress,
        generation: Int
    ) -> Bool {
        generations[walletID] == generation
            && rows.first(where: { $0.id == walletID })?.wallet.address == address
    }

    private func invalidateRequest(for id: UUID) {
        generations[id, default: 0] += 1
        portfolioTasks.removeValue(forKey: id)?.cancel()
    }

    private func updateRow(
        id: UUID,
        update: (inout WalletListRowViewModel) -> Void
    ) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        update(&rows[index])
    }
}
