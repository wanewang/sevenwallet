//
//  Formatting.swift
//  System · number / address formatting.
//

import Foundation

enum Fmt {
    static func usd(_ n: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = "USD"
        f.maximumFractionDigits = 2; f.minimumFractionDigits = 2
        return f.string(from: n as NSNumber) ?? "$0.00"
    }
    static func amount(_ n: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal
        f.minimumFractionDigits = 2; f.maximumFractionDigits = 4
        return f.string(from: n as NSNumber) ?? "0"
    }
    static func pct(_ n: Double) -> String { (n > 0 ? "+" : "") + String(format: "%.2f%%", n) }
    static func short(_ a: String) -> String {
        guard a.count > 12 else { return a }
        return a.prefix(6) + "…" + a.suffix(4)
    }
}
