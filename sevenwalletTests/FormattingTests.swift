import Foundation
import Testing
@testable import sevenwallet

struct FormattingTests {
    @Test
    func shortAddressUsesSixCharactersOnEachSide() {
        #expect(Fmt.short("0x1234567890ABCDEF") == "0x1234…ABCDEF")
    }

    @Test
    func shortAddressLeavesTwelveCharactersUntouched() {
        #expect(Fmt.short("123456789012") == "123456789012")
    }

    @Test
    func percentageFormattingCoversAllSigns() {
        #expect(Fmt.pct(2.48) == "+2.48%")
        #expect(Fmt.pct(-0.03) == "-0.03%")
        #expect(Fmt.pct(0) == "0.00%")
    }

    @Test
    func usdFormattingIsDeterministic() {
        #expect(Fmt.usd(12_480.21) == "$12,480.21")
    }

    @Test
    func decimalFormattingIsExact() {
        #expect(Fmt.usd(Decimal(string: "1926.42")!) == "$1,926.42")
        #expect(Fmt.amount(Decimal(string: "0.0934")!) == "0.0934")
        #expect(Fmt.pct(nil as Decimal?) == "-")
    }
}
