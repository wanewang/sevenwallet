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
        let body = normalized.dropFirst(2)
        guard normalized.hasPrefix("0x"), body.count == 40, body.allSatisfy(\.isHexDigit) else {
            throw Error.invalid(raw)
        }
        rawValue = normalized
    }

    init(rawValue: String) {
        precondition((try? EVMAddress(rawValue)) != nil)
        self.rawValue = rawValue.lowercased()
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
