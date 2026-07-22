import Foundation

struct AppConfiguration: Sendable {
    enum Error: Swift.Error, Equatable, LocalizedError {
        case missingBaseURL
        case invalidBaseURL(String)

        nonisolated var errorDescription: String? {
            switch self {
            case .missingBaseURL:
                "BASE_URL is not configured."
            case .invalidBaseURL:
                "BASE_URL is invalid."
            }
        }
    }

    let baseURL: URL

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]
    ) throws {
        let environmentValue = environment["BASE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let bundleValue = (infoDictionary["BASE_URL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw = [environmentValue, bundleValue].compactMap({ $0 }).first(where: { !$0.isEmpty }) else {
            throw Error.missingBaseURL
        }
        guard var parts = URLComponents(string: raw),
              let scheme = parts.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              parts.host != nil,
              parts.user == nil,
              parts.password == nil,
              parts.query == nil,
              parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/" else {
            throw Error.invalidBaseURL(raw)
        }
        parts.path = ""
        guard let url = parts.url else { throw Error.invalidBaseURL(raw) }
        baseURL = url
    }
}
