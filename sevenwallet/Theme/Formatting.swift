//
//  Formatting.swift
//  System · number / address formatting.
//

import Foundation

enum Fmt {
    static func usd(_ n: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: n as NSNumber) ?? "$0.00"
    }
    static func amount(_ n: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 4
        return formatter.string(from: n as NSNumber) ?? "0"
    }
    static func pct(_ n: Double) -> String {
        (n > 0 ? "+" : "") + String(format: "%.2f%%", n)
    }
    static func short(_ address: String) -> String {
        guard address.count > 12 else { return address }
        return String(address.prefix(6)) + "…" + String(address.suffix(6))
    }
}
