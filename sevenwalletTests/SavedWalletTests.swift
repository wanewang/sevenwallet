import Foundation
import Testing
@testable import sevenwallet

struct SavedWalletTests {
    private let validAddress = "0x71A2B3C4D5E6F7890A1B2C3D4E5F67890ABC8F92"

    @Test func nameTrimsAndAcceptsTwentyCharacters() {
        #expect(WalletInputValidator.validatedName("  Main Wallet  ") == "Main Wallet")
        #expect(WalletInputValidator.validatedName(String(repeating: "a", count: 20)) != nil)
        #expect(WalletInputValidator.validatedName("   ") == nil)
        #expect(WalletInputValidator.validatedName(String(repeating: "a", count: 21)) == nil)
    }

    @Test func nameInputIsCappedBySwiftCharacters() {
        #expect(WalletInputValidator.limitedName("12345678901234567890x") == "12345678901234567890")
        #expect(WalletInputValidator.limitedName(String(repeating: "🙂", count: 21)).count == 20)
    }

    @Test func addressTrimsValidatesAndNormalizes() throws {
        let address = try #require(WalletInputValidator.validatedAddress("  \(validAddress)  "))
        #expect(address.rawValue == validAddress.lowercased())
        #expect(WalletInputValidator.validatedAddress("0x1234") == nil)
        #expect(WalletInputValidator.validatedAddress(
            "0x71A2B3C4D5E6F7890A1B2C3D4E5F67890ABC8F9Z"
        ) == nil)
    }

    @Test func colorsAreStableAndComplete() {
        #expect(WalletCardColor.allCases == [.blue, .purple, .pink, .teal, .amber])
        #expect(Set(WalletCardColor.allCases.map(\.rawValue)).count == 5)
    }

    @Test func walletKeepsStableIdentity() throws {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 100)
        let wallet = SavedWallet(
            id: id,
            name: "Main",
            address: try EVMAddress(validAddress),
            cardColor: .teal,
            createdAt: date
        )
        #expect(wallet.id == id)
        #expect(wallet.name == "Main")
        #expect(wallet.cardColor == .teal)
        #expect(wallet.createdAt == date)
    }
}
