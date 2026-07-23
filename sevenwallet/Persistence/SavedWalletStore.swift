import Foundation
import SwiftData

nonisolated struct SavedWalletSnapshot: Equatable, Sendable {
    let wallets: [SavedWallet]
    let selectedWalletID: UUID?

    var selectedWallet: SavedWallet? {
        wallets.first { $0.id == selectedWalletID } ?? wallets.first
    }
}

protocol SavedWalletStoreProtocol: Sendable {
    func loadSnapshot() async throws -> SavedWalletSnapshot
    func addAndSelect(_ wallet: SavedWallet) async throws -> SavedWalletSnapshot
    func update(
        id: UUID,
        name: String,
        cardColor: WalletCardColor
    ) async throws -> SavedWalletSnapshot
    func delete(id: UUID) async throws -> SavedWalletSnapshot
}

enum SavedWalletStoreError: Error, Equatable {
    case walletNotFound
    case corruptRecord
}

@ModelActor
actor SavedWalletStore: SavedWalletStoreProtocol {
    func loadSnapshot() throws -> SavedWalletSnapshot {
        let wallets = try wallets()
        let storedSelection = try selectionRecord()?.walletID
        let resolvedSelection = wallets.contains { $0.id == storedSelection }
            ? storedSelection
            : wallets.first?.id
        if storedSelection != resolvedSelection {
            do {
                try setSelection(resolvedSelection)
                try modelContext.save()
            } catch {
                modelContext.rollback()
                throw error
            }
        }
        return SavedWalletSnapshot(
            wallets: wallets,
            selectedWalletID: resolvedSelection
        )
    }

    func addAndSelect(_ wallet: SavedWallet) throws -> SavedWalletSnapshot {
        do {
            modelContext.insert(SavedWalletRecord(wallet: wallet))
            try setSelection(wallet.id)
            let snapshot = try snapshot()
            try modelContext.save()
            return snapshot
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func update(
        id: UUID,
        name: String,
        cardColor: WalletCardColor
    ) throws -> SavedWalletSnapshot {
        var descriptor = FetchDescriptor<SavedWalletRecord>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        guard let record = try modelContext.fetch(descriptor).first else {
            throw SavedWalletStoreError.walletNotFound
        }
        do {
            record.name = name
            record.cardColor = cardColor.rawValue
            let snapshot = try snapshot()
            try modelContext.save()
            return snapshot
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func delete(id: UUID) throws -> SavedWalletSnapshot {
        var descriptor = FetchDescriptor<SavedWalletRecord>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        guard let record = try modelContext.fetch(descriptor).first else {
            throw SavedWalletStoreError.walletNotFound
        }
        do {
            let storedSelection = try selectionRecord()?.walletID
            let remaining = try wallets().filter { $0.id != id }
            modelContext.delete(record)
            let selectionStillExists = remaining.contains {
                $0.id == storedSelection
            }
            if storedSelection == id || !selectionStillExists {
                try setSelection(remaining.first?.id)
            }
            let snapshot = try snapshot()
            try modelContext.save()
            return snapshot
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func snapshot() throws -> SavedWalletSnapshot {
        SavedWalletSnapshot(
            wallets: try wallets(),
            selectedWalletID: try selectionRecord()?.walletID
        )
    }

    private func wallets() throws -> [SavedWallet] {
        let records = try modelContext.fetch(FetchDescriptor<SavedWalletRecord>())
            .sorted {
                if $0.createdAt == $1.createdAt {
                    $0.id.uuidString < $1.id.uuidString
                } else {
                    $0.createdAt < $1.createdAt
                }
            }
        return try records.map { record in
            guard let address = EVMAddress(rawValue: record.address),
                  let color = WalletCardColor(rawValue: record.cardColor) else {
                throw SavedWalletStoreError.corruptRecord
            }
            return SavedWallet(
                id: record.id,
                name: record.name,
                address: address,
                cardColor: color,
                createdAt: record.createdAt
            )
        }
    }

    private func selectionRecord() throws -> WalletSelectionRecord? {
        var descriptor = FetchDescriptor<WalletSelectionRecord>(
            predicate: #Predicate { $0.key == "selected" }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func setSelection(_ id: UUID?) throws {
        if let record = try selectionRecord() {
            if let id {
                record.walletID = id
            } else {
                modelContext.delete(record)
            }
        } else if let id {
            modelContext.insert(WalletSelectionRecord(walletID: id))
        }
    }
}
