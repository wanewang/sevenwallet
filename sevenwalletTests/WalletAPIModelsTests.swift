import Foundation
import Testing
@testable import sevenwallet

struct WalletAPIModelsTests {
    @Test func addressNormalizes() throws {
        let address = try EVMAddress("0x71A2B3C4D5E6F7890A1B2C3D4E5F67890ABC8F92")
        #expect(address.rawValue == "0x71a2b3c4d5e6f7890a1b2c3d4e5f67890abc8f92")
    }

    @Test(arguments: ["", "71a2", "0x1234", "0x71A2B3C4D5E6F7890A1B2C3D4E5F67890ABC8F9Z"])
    func invalidAddressFails(_ raw: String) {
        #expect(throws: EVMAddress.Error.invalid(raw)) { try EVMAddress(raw) }
    }

    @Test func malformedAddressDecodingFails() {
        let data = Data(#""0x1234""#.utf8)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(EVMAddress.self, from: data)
        }
    }

    @Test func invalidAddressHasConciseDescription() {
        #expect(EVMAddress.Error.invalid("private address").localizedDescription == "Wallet address is invalid.")
    }

    @Test func contractTokenKeyUsesSymbolAndNormalizedAddress() {
        let token = makeToken(symbol: "USDC", tokenAddress: "0xABC", coinKey: "usd-coin")

        #expect(token.key == "USDC:0xabc")
        #expect(token.id == token.key)
    }

    @Test func nativeTokenKeyUsesNativeMarker() {
        let token = makeToken(symbol: "ETH", tokenAddress: nil, coinKey: nil)

        #expect(token.key == "ETH:native")
        #expect(token.id == "ETH:native")
    }

    @Test func coinKeyDoesNotAffectTokenKey() {
        let first = makeToken(symbol: "ETH", tokenAddress: nil, coinKey: "ethereum")
        let second = makeToken(symbol: "ETH", tokenAddress: nil, coinKey: nil)

        #expect(first.key == second.key)
    }

    private func makeToken(symbol: String, tokenAddress: String?, coinKey: String?) -> WalletToken {
        WalletToken(
            tokenAddress: tokenAddress,
            symbol: symbol,
            name: "Ethereum",
            decimals: 18,
            rawBalance: "0",
            balance: 0,
            isNative: true,
            price: nil,
            logoURL: nil,
            change24hPercent: nil,
            coinKey: coinKey,
            marketCapUSD: nil,
            marketDataUpdatedAt: nil,
            priceUSD: nil
        )
    }
}
