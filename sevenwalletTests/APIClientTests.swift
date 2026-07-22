import Foundation
import Testing
@testable import sevenwallet

@MainActor
@Suite(.serialized)
struct APIClientTests {
    @Test func nativeUsesV1AndDecodesNullAddress() async throws {
        let (client, recorder) = makeClient(
            status: 200,
            body: #"[{"tokenAddress":null,"symbol":"ETH","name":"Ethereum","decimals":18,"rawBalance":"0","balance":"0","isNative":true,"price":{"currency":"usd","value":"1926.42","lastUpdatedAt":"2026-07-22T19:26:30Z"},"logoURI":null,"coinKey":"ETH","priceUSD":"1926.42"}]"#
        )

        let tokens = try await TokenRemoteDataSource(client: client).fetchNativeTokens()

        #expect(await recorder.lastRequest?.url?.absoluteString == "https://wallet.example/v1/native")
        #expect(tokens.first?.tokenAddress == nil)
        #expect(tokens.first?.balance == Decimal.zero)
        #expect(tokens.first?.price?.value == Decimal(string: "1926.42"))
        #expect(tokens.first?.price?.lastUpdatedAt == ISO8601DateFormatter().date(from: "2026-07-22T19:26:30Z"))
        #expect(tokens.first?.priceUSD == Decimal(string: "1926.42"))
    }

    @Test func transactionQueryIsEncoded() throws {
        let address = try EVMAddress("0x71A2B3C4D5E6F7890A1B2C3D4E5F67890ABC8F92")
        let endpoint = APIEndpoint.transactions(address, limit: 100, pageKey: "next key")

        #expect(endpoint.queryItems == [
            URLQueryItem(name: "limit", value: "100"),
            URLQueryItem(name: "pageKey", value: "next key")
        ])
    }

    @Test func transactionWithoutCursorOnlyUsesLimit() throws {
        let address = try EVMAddress("0x71A2B3C4D5E6F7890A1B2C3D4E5F67890ABC8F92")

        #expect(APIEndpoint.transactions(address, limit: 25, pageKey: nil).queryItems == [
            URLQueryItem(name: "limit", value: "25")
        ])
    }

    @Test func serverErrorIsTyped() async {
        let (client, _) = makeClient(status: 503, body: #"{"error":"upstream unavailable"}"#)

        await #expect(throws: APIError.http(status: 503, message: "upstream unavailable")) {
            try await client.data(for: .nativeTokens)
        }
    }

    @Test func serverErrorWithoutErrorPayloadHasNoMessage() async {
        let (client, _) = makeClient(status: 500, body: #"{"message":"failed"}"#)

        await #expect(throws: APIError.http(status: 500, message: nil)) {
            try await client.data(for: .nativeTokens)
        }
    }

    @Test func transportErrorIsTyped() async {
        let expected = URLError(.timedOut)
        let client = makeFailingClient(error: expected)

        await #expect(throws: APIError.transport(expected.localizedDescription)) {
            try await client.data(for: .nativeTokens)
        }
    }

    @Test func nonHTTPResponseIsTyped() async {
        let client = makeNonHTTPClient(body: "[]")

        await #expect(throws: APIError.nonHTTPResponse) {
            try await client.data(for: .nativeTokens)
        }
    }

    @Test func portfolioMapsDocumentedFieldsAndNormalizedRequest() async throws {
        let requested = try EVMAddress("0x71A2B3C4D5E6F7890A1B2C3D4E5F67890ABC8F92")
        let (client, recorder) = makeClient(
            status: 200,
            body: #"{"address":"0x71A2B3C4D5E6F7890A1B2C3D4E5F67890ABC8F92","fetchedAt":"2026-07-22T19:26:30Z","network":"ethereum","tokens":[{"tokenAddress":"0x1111111111111111111111111111111111111111","symbol":"USDC","name":"USD Coin","decimals":6,"rawBalance":"2500000","balance":"2.5","isNative":false,"price":{"currency":null,"value":null,"lastUpdatedAt":null},"logoURI":"https://assets.example/usdc.png","coinKey":"USDC","priceUSD":null}]}"#
        )

        let portfolio = try await TokenRemoteDataSource(client: client).fetchPortfolio(address: requested)

        #expect(await recorder.lastRequest?.url?.absoluteString == "https://wallet.example/v1/addresses/0x71a2b3c4d5e6f7890a1b2c3d4e5f67890abc8f92/tokens")
        #expect(portfolio.address == requested)
        #expect(portfolio.network == "ethereum")
        #expect(portfolio.tokens.count == 1)
        #expect(portfolio.tokens.first?.balance == Decimal(string: "2.5"))
        #expect(portfolio.tokens.first?.logoURL?.absoluteString == "https://assets.example/usdc.png")
        #expect(portfolio.tokens.first?.price?.currency == nil)
    }

    @Test func portfolioRejectsDifferentReturnedAddress() async throws {
        let requested = try EVMAddress("0x71A2B3C4D5E6F7890A1B2C3D4E5F67890ABC8F92")
        let (client, _) = makeClient(
            status: 200,
            body: #"{"address":"0x1111111111111111111111111111111111111111","fetchedAt":null,"network":null,"tokens":[]}"#
        )

        await #expect(throws: APIError.invalidData) {
            try await TokenRemoteDataSource(client: client).fetchPortfolio(address: requested)
        }
    }

    @Test func transactionsMapCursorTransfersAndEncodedRequest() async throws {
        let requested = try EVMAddress("0x71A2B3C4D5E6F7890A1B2C3D4E5F67890ABC8F92")
        let (client, recorder) = makeClient(
            status: 200,
            body: #"{"address":"0x71A2B3C4D5E6F7890A1B2C3D4E5F67890ABC8F92","nextPageKey":"cursor-2","transfers":[{"asset":"ETH","blockNum":"0x123","category":"external","from":"0x1111111111111111111111111111111111111111","hash":"0xabc","to":"0x2222222222222222222222222222222222222222","value":"1.25"},{"asset":null,"blockNum":null,"category":null,"from":null,"hash":null,"to":null,"value":null}]}"#
        )

        let page = try await TransactionRemoteDataSource(client: client).fetchTransactions(
            address: requested,
            limit: 100,
            pageKey: "next key"
        )

        #expect(await recorder.lastRequest?.url?.absoluteString == "https://wallet.example/v1/addresses/0x71a2b3c4d5e6f7890a1b2c3d4e5f67890abc8f92/transactions?limit=100&pageKey=next%20key")
        #expect(page.address == requested)
        #expect(page.nextPageKey == "cursor-2")
        #expect(page.transfers.count == 2)
        #expect(page.transfers.first?.blockNumber == "0x123")
        #expect(page.transfers.first?.hash == "0xabc")
        #expect(page.transfers.last?.hash == nil)
    }

    @Test func transactionsRejectDifferentReturnedAddress() async throws {
        let requested = try EVMAddress("0x71A2B3C4D5E6F7890A1B2C3D4E5F67890ABC8F92")
        let (client, _) = makeClient(
            status: 200,
            body: #"{"address":"0x1111111111111111111111111111111111111111","nextPageKey":null,"transfers":[]}"#
        )

        await #expect(throws: APIError.invalidData) {
            try await TransactionRemoteDataSource(client: client).fetchTransactions(
                address: requested,
                limit: 25,
                pageKey: nil
            )
        }
    }

    @Test func invalidRequiredNumericStringIsInvalidData() async {
        let (client, _) = makeClient(
            status: 200,
            body: #"[{"tokenAddress":null,"symbol":"ETH","name":"Ethereum","decimals":18,"rawBalance":"0","balance":"not-a-number","isNative":true,"price":null,"logoURI":null,"coinKey":"ETH","priceUSD":null}]"#
        )

        await #expect(throws: APIError.invalidData) {
            try await TokenRemoteDataSource(client: client).fetchNativeTokens()
        }
    }

    @Test func partiallyNumericRequiredBalanceIsInvalidData() async {
        let (client, _) = makeClient(
            status: 200,
            body: #"[{"tokenAddress":null,"symbol":"ETH","name":"Ethereum","decimals":18,"rawBalance":"0","balance":"1oops","isNative":true,"price":null,"logoURI":null,"coinKey":"ETH","priceUSD":null}]"#
        )

        await #expect(throws: APIError.invalidData) {
            try await TokenRemoteDataSource(client: client).fetchNativeTokens()
        }
    }

    @Test func partiallyNumericPriceValueIsInvalidData() async {
        let (client, _) = makeClient(
            status: 200,
            body: #"[{"tokenAddress":null,"symbol":"ETH","name":"Ethereum","decimals":18,"rawBalance":"0","balance":"1","isNative":true,"price":{"currency":"usd","value":"1.2.3","lastUpdatedAt":null},"logoURI":null,"coinKey":"ETH","priceUSD":null}]"#
        )

        await #expect(throws: APIError.invalidData) {
            try await TokenRemoteDataSource(client: client).fetchNativeTokens()
        }
    }

    @Test func partiallyNumericPriceUSDIsInvalidData() async {
        let (client, _) = makeClient(
            status: 200,
            body: #"[{"tokenAddress":null,"symbol":"ETH","name":"Ethereum","decimals":18,"rawBalance":"0","balance":"1","isNative":true,"price":null,"logoURI":null,"coinKey":"ETH","priceUSD":"2oops"}]"#
        )

        await #expect(throws: APIError.invalidData) {
            try await TokenRemoteDataSource(client: client).fetchNativeTokens()
        }
    }

    @Test func malformedSuccessPayloadIsInvalidData() async {
        let (client, _) = makeClient(status: 200, body: #"{"unexpected":true}"#)

        await #expect(throws: APIError.invalidData) {
            try await TokenRemoteDataSource(client: client).fetchNativeTokens()
        }
    }
}

private actor RequestRecorder {
    private(set) var lastRequest: URLRequest?

    func record(_ request: URLRequest) {
        lastRequest = request
    }
}

private final class URLProtocolStub: URLProtocol {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) async throws -> (URLResponse, Data))?

    private var responseTask: Task<Void, Never>?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        responseTask = Task {
            do {
                let (response, data) = try await handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }

    override func stopLoading() {
        responseTask?.cancel()
    }
}

private func makeClient(status: Int, body: String) -> (APIClient, RequestRecorder) {
    let recorder = RequestRecorder()
    let data = Data(body.utf8)
    URLProtocolStub.handler = { request in
        await recorder.record(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, data)
    }
    return (makeClient(), recorder)
}

private func makeFailingClient(error: any Error) -> APIClient {
    URLProtocolStub.handler = { _ in throw error }
    return makeClient()
}

private func makeNonHTTPClient(body: String) -> APIClient {
    let data = Data(body.utf8)
    URLProtocolStub.handler = { request in
        (URLResponse(url: request.url!, mimeType: nil, expectedContentLength: data.count, textEncodingName: nil), data)
    }
    return makeClient()
}

private func makeClient() -> APIClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [URLProtocolStub.self]
    return APIClient(
        baseURL: URL(string: "https://wallet.example")!,
        session: URLSession(configuration: configuration)
    )
}
