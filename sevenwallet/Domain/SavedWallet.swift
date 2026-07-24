import Foundation

nonisolated enum WalletCardColor: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case blue
    case purple
    case pink
    case teal
    case amber

    var id: String { rawValue }
}

nonisolated struct SavedWallet: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let name: String
    let address: EVMAddress
    let cardColor: WalletCardColor
    let createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        address: EVMAddress,
        cardColor: WalletCardColor,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.cardColor = cardColor
        self.createdAt = createdAt
    }
}

nonisolated enum WalletInputValidator {
    static let maximumNameLength = 20

    static func limitedName(_ value: String) -> String {
        String(value.prefix(maximumNameLength))
    }

    static func validatedName(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maximumNameLength else { return nil }
        return trimmed
    }

    static func validatedAddress(_ value: String) -> EVMAddress? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return try? EVMAddress(trimmed)
    }
}
