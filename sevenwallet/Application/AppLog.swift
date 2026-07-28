import Foundation
import os

enum AppLog {
    static let market = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "sevenwallet",
        category: "market"
    )

    static func marketError(_ message: String) {
        market.error("\(message, privacy: .public)")
    }

    static func marketWarning(_ message: String) {
        market.warning("\(message, privacy: .public)")
    }
}
