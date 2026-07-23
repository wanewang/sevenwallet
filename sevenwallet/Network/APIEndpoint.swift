import Foundation

enum APIEndpoint: Equatable, Sendable {
    case nativeTokens
    case portfolio(EVMAddress)
    case transactions(EVMAddress, limit: Int, pageKey: String?)

    var path: String {
        switch self {
        case .nativeTokens:
            "/v1/native"
        case .portfolio(let address):
            "/v1/addresses/\(address.rawValue)/tokens"
        case .transactions(let address, _, _):
            "/v1/addresses/\(address.rawValue)/transactions"
        }
    }

    var queryItems: [URLQueryItem] {
        guard case .transactions(_, let limit, let pageKey) = self else { return [] }
        var result = [URLQueryItem(name: "limit", value: String(limit))]
        if let pageKey {
            result.append(URLQueryItem(name: "pageKey", value: pageKey))
        }
        return result
    }
}
