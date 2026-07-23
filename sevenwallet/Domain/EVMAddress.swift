import Foundation

nonisolated struct EVMAddress: RawRepresentable, Codable, Hashable, Sendable {
    enum Error: Swift.Error, Equatable, LocalizedError {
        case invalid(String)

        nonisolated var errorDescription: String? {
            "Wallet address is invalid."
        }
    }

    let rawValue: String

    init(_ raw: String) throws {
        let normalized = raw.lowercased()
        let body = normalized.utf8.dropFirst(2)
        guard normalized.hasPrefix("0x"), body.count == 40,
              body.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw Error.invalid(raw)
        }
        rawValue = normalized
    }

    init?(rawValue: String) {
        guard let address = try? EVMAddress(rawValue) else { return nil }
        self = address
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        do {
            self = try EVMAddress(rawValue)
        } catch {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid EVM address")
        }
    }
}
