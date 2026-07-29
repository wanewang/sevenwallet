import Foundation
import SwiftData

@Model
final class SavedWalletRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var address: String
    var cardColor: String
    var createdAt: Date
    var credentialReferenceID: UUID?

    init(wallet: SavedWallet) {
        id = wallet.id
        name = wallet.name
        address = wallet.address.rawValue
        cardColor = wallet.cardColor.rawValue
        createdAt = wallet.createdAt
        credentialReferenceID = wallet.credentialReference?.rawValue
    }
}

@Model
final class WalletSelectionRecord {
    @Attribute(.unique) var key = "selected"
    var walletID: UUID

    init(walletID: UUID) {
        self.walletID = walletID
    }
}
