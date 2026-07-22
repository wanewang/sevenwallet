//
//  Formatting.swift
//  System · number / address formatting.
//

import Foundation

enum Fmt {
    static func usd(_ n: Double) -> String {
        let value = decimalFormatter(minimum: 2, maximum: 2).string(from: abs(n) as NSNumber) ?? "0.00"
        return (n < 0 ? "-$" : "$") + value
    }

    static func usd(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value)
        let negative = number.compare(NSDecimalNumber.zero) == .orderedAscending
        let magnitude = negative ? number.multiplying(by: -1) : number
        return (negative ? "-$" : "$") + (decimalFormatter(minimum: 2, maximum: 2).string(from: magnitude) ?? "0.00")
    }

    static func amount(_ n: Double) -> String {
        decimalFormatter(minimum: 2, maximum: 4).string(from: n as NSNumber) ?? "0"
    }

    static func amount(_ value: Decimal) -> String {
        decimalFormatter(minimum: 2, maximum: 4).string(from: NSDecimalNumber(decimal: value)) ?? "0"
    }

    static func pct(_ n: Double) -> String {
        (n > 0 ? "+" : "") + String(format: "%.2f%%", n)
    }

    static func pct(_ value: Decimal?) -> String {
        guard let value else { return "-" }
        let number = NSDecimalNumber(decimal: value)
        return (number.compare(NSDecimalNumber.zero) == .orderedDescending ? "+" : "") + String(format: "%.2f%%", number.doubleValue)
    }

    static func short(_ address: String) -> String {
        guard address.count > 12 else { return address }
        return String(address.prefix(6)) + "…" + String(address.suffix(6))
    }

    private static func decimalFormatter(minimum: Int, maximum: Int) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.decimalSeparator = "."
        formatter.minimumFractionDigits = minimum
        formatter.maximumFractionDigits = maximum
        return formatter
    }
}
