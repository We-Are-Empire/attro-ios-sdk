import Testing
import Foundation
@testable import AttroSDK

/// Money objects (contract §6): exact decimal strings and integer minor
/// units, never floats.
@Suite("Money decoding")
struct MoneyTests {
    private func decode(_ json: String) throws -> Money {
        try JSONDecoder().decode(Money.self, from: Data(json.utf8))
    }

    @Test("Decodes the contract test's values exactly", arguments: [
        ("USD", Int64(1234), "12.34", 2),
        ("JPY", Int64(1500), "1500", 0),
        ("USD", Int64(80000), "800.00", 2),
        ("KWD", Int64(1234), "1.234", 3),
        ("USD", Int64(0), "0.00", 2),
        ("EUR", Int64(-250), "-2.50", 2),
    ])
    func exact(currency: String, minor: Int64, major: String, exponent: Int) throws {
        let money = try decode(#"{"amount":"\#(major)","amountMinor":\#(minor),"currency":"\#(currency)"}"#)
        #expect(money.amountString == major)
        #expect(money.amountMinor == minor)
        #expect(money.currency == currency)
        #expect(money.minorUnitExponent == exponent)
        #expect(money.amount == Decimal(string: major, locale: Locale(identifier: "en_US_POSIX")))
    }

    @Test("Amounts beyond Double's precision stay exact")
    func beyondDouble() throws {
        // 2^53 + 1 minor units: a Double cannot represent this value.
        let money = try decode(#"{"amount":"90071992547409.93","amountMinor":9007199254740993,"currency":"USD"}"#)
        #expect(money.amountMinor == 9_007_199_254_740_993)
        #expect(money.amount.description == "90071992547409.93")
    }

    @Test("Refuses a JSON number as amount (a float in disguise)")
    func numberAmount() {
        #expect(throws: DecodingError.self) {
            try decode(#"{"amount":12.34,"amountMinor":1234,"currency":"USD"}"#)
        }
    }

    @Test("Refuses a non-integer amountMinor")
    func fractionalMinor() {
        #expect(throws: DecodingError.self) {
            try decode(#"{"amount":"12.34","amountMinor":1234.5,"currency":"USD"}"#)
        }
    }

    @Test("Refuses amount and amountMinor that disagree")
    func mismatch() {
        #expect(throws: DecodingError.self) {
            try decode(#"{"amount":"12.34","amountMinor":1235,"currency":"USD"}"#)
        }
        #expect(throws: Money.ValidationError.amountMismatch(amount: "12.3", amountMinor: 1234)) {
            try Money(amount: "12.3", amountMinor: 1234, currency: "USD")
        }
    }

    @Test("Refuses malformed amounts and currencies", arguments: [
        #"{"amount":"12,34","amountMinor":1234,"currency":"USD"}"#,
        #"{"amount":"1e3","amountMinor":1000,"currency":"USD"}"#,
        #"{"amount":"12.","amountMinor":12,"currency":"USD"}"#,
        #"{"amount":".5","amountMinor":5,"currency":"USD"}"#,
        #"{"amount":" 12.34","amountMinor":1234,"currency":"USD"}"#,
        #"{"amount":"12.34","amountMinor":1234,"currency":"usd"}"#,
        #"{"amount":"12.34","amountMinor":1234,"currency":"US"}"#,
        #"{"amount":"12.34","amountMinor":1234}"#,
        #"{"amountMinor":1234,"currency":"USD"}"#,
    ])
    func malformed(_ json: String) {
        #expect(throws: DecodingError.self) { try decode(json) }
    }

    @Test("Encodes back to the exact wire shape")
    func roundTrip() throws {
        let money = try decode(#"{"amount":"1500","amountMinor":1500,"currency":"JPY"}"#)
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(money)) as? [String: Any]
        #expect(object?["amount"] as? String == "1500")
        #expect((object?["amountMinor"] as? NSNumber)?.int64Value == 1500)
        #expect(object?["currency"] as? String == "JPY")
        #expect(Set(object?.keys.map { $0 } ?? []) == ["amount", "amountMinor", "currency"])
    }

    @Test("Formats from the exact decimal with the currency's exponent")
    func formatting() throws {
        let usd = try Money(amount: "12.50", amountMinor: 1250, currency: "USD")
        #expect(usd.formatted(locale: Locale(identifier: "en_US")) == "$12.50")
        let jpy = try Money(amount: "1500", amountMinor: 1500, currency: "JPY")
        #expect(jpy.formatted(locale: Locale(identifier: "en_US")).contains("1,500"))
        #expect(usd.description == "12.50 USD")
    }

    @Test("my-affiliate stats.earnings decodes as Money (USD and JPY fixtures)", arguments: [
        ("my-affiliate-usd", "12.34", Int64(1234), "USD"),
        ("my-affiliate-jpy", "1500", Int64(1500), "JPY"),
    ])
    func affiliateEarnings(fixture: String, amount: String, minor: Int64, currency: String) throws {
        let info = try JSONDecoder().decode(AffiliateInfo.self, from: Fixture.data(fixture))
        #expect(info.stats.earnings.amountString == amount)
        #expect(info.stats.earnings.amountMinor == minor)
        #expect(info.stats.earnings.currency == currency)
        #expect(!info.stats.earningsFormatted.isEmpty)
    }

    @Test("The retired v1 earnings shape (a float plus earningsMinor) is refused")
    func legacyEarningsRefused() throws {
        var object = Fixture.json("my-affiliate-usd")
        var stats = object["stats"] as! [String: Any]
        stats["earnings"] = 12.34
        stats["earningsMinor"] = 1234
        stats["currency"] = "USD"
        object["stats"] = stats
        let data = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(AffiliateInfo.self, from: data)
        }
    }
}
