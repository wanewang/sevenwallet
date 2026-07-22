import Foundation

struct EVMAddress: RawRepresentable, Codable, Hashable, Sendable {
    enum Error: Swift.Error, Equatable {
        case invalid(String)
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
}
