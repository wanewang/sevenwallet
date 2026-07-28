import Foundation
import os

enum AppLog {
    static let market = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "sevenwallet",
        category: "market"
    )
}
