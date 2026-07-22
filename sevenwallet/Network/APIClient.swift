import Foundation

enum APIError: Swift.Error, Equatable {
    case invalidRequest
    case transport(String)
    case nonHTTPResponse
    case http(status: Int, message: String?)
    case invalidData
}

protocol APIClientProtocol: Sendable {
    func data(for endpoint: APIEndpoint) async throws -> Data
}

struct APIClient: APIClientProtocol, Sendable {
    let baseURL: URL
    let session: URLSession

    func data(for endpoint: APIEndpoint) async throws -> Data {
        guard var parts = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidRequest
        }
        parts.path = endpoint.path
        parts.queryItems = endpoint.queryItems.isEmpty ? nil : endpoint.queryItems
        guard let url = parts.url else { throw APIError.invalidRequest }

        do {
            let (data, response) = try await session.data(for: URLRequest(url: url))
            guard let http = response as? HTTPURLResponse else {
                throw APIError.nonHTTPResponse
            }
            guard 200..<300 ~= http.statusCode else {
                let message = try? JSONDecoder().decode(ErrorPayload.self, from: data).error
                throw APIError.http(status: http.statusCode, message: message)
            }
            return data
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
    }
}

private struct ErrorPayload: Decodable {
    let error: String
}
