import Foundation

/// An exact amount of money, as Attro returns it in every `/api/ios/**`
/// response (contract §6):
///
/// ```json
/// { "amount": "12.50", "amountMinor": 1250, "currency": "USD" }
/// ```
///
/// - `amount` is a decimal string in major units, written with the currency's
///   exponent (JPY has none: `"1500"`).
/// - `amountMinor` is an integer count of minor units.
///
/// Money is never a binary floating-point number. The SDK decodes `amount`
/// from its string into a `Decimal` (exact), decodes `amountMinor` as an
/// integer, and refuses any payload where the two disagree, where `amount` is
/// a JSON number, or where `amountMinor` is not an integer.
public struct Money: Codable, Sendable, Hashable, CustomStringConvertible {
    /// The exact amount in major units (for example `12.50`).
    public let amount: Decimal

    /// The amount exactly as the server wrote it (for example `"12.50"`).
    public let amountString: String

    /// The amount in minor units (for example `1250`).
    public let amountMinor: Int64

    /// ISO 4217 currency code, upper case (for example `"USD"`).
    public let currency: String

    /// Digits after the decimal point in `amountString`: the currency's
    /// exponent as the server applied it (2 for USD, 0 for JPY, 3 for KWD).
    public let minorUnitExponent: Int

    /// Why a Money value was refused.
    public enum ValidationError: Error, Equatable, Sendable {
        /// `amount` is not a plain decimal string (`-?digits[.digits]`).
        case malformedAmount(String)
        /// `amount` and `amountMinor` do not describe the same value.
        case amountMismatch(amount: String, amountMinor: Int64)
        /// `currency` is not three upper-case letters.
        case malformedCurrency(String)
    }

    /// Build a Money value from its wire fields, validating that they agree.
    public init(amount: String, amountMinor: Int64, currency: String) throws {
        guard Self.isCurrencyCode(currency) else {
            throw ValidationError.malformedCurrency(currency)
        }
        guard let parsed = Self.parseDecimal(amount) else {
            throw ValidationError.malformedAmount(amount)
        }
        guard parsed.minor == amountMinor else {
            throw ValidationError.amountMismatch(amount: amount, amountMinor: amountMinor)
        }
        guard let decimal = Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX")) else {
            throw ValidationError.malformedAmount(amount)
        }
        self.amount = decimal
        self.amountString = amount
        self.amountMinor = amountMinor
        self.currency = currency
        self.minorUnitExponent = parsed.scale
    }

    private enum CodingKeys: String, CodingKey {
        case amount, amountMinor, currency
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // A JSON number here is a contract violation (a float in disguise):
        // decode strictly as a String so it fails instead of being rounded.
        let amount = try container.decode(String.self, forKey: .amount)
        let amountMinor = try container.decode(Int64.self, forKey: .amountMinor)
        let currency = try container.decode(String.self, forKey: .currency)
        do {
            try self.init(amount: amount, amountMinor: amountMinor, currency: currency)
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .amount,
                in: container,
                debugDescription: "Invalid Money object: \(error)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(amountString, forKey: .amount)
        try container.encode(amountMinor, forKey: .amountMinor)
        try container.encode(currency, forKey: .currency)
    }

    /// `"12.50 USD"`: the exact wire amount and its currency.
    public var description: String { "\(amountString) \(currency)" }

    /// The amount formatted for display in `locale`, using the exact decimal.
    /// Prefer the server's own display string where the response has one
    /// (for example `stats.earningsFormatted`).
    public func formatted(locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        formatter.currencyCode = currency
        formatter.minimumFractionDigits = minorUnitExponent
        formatter.maximumFractionDigits = minorUnitExponent
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? description
    }

    // MARK: - Parsing

    private static func isCurrencyCode(_ value: String) -> Bool {
        value.utf8.count == 3 && value.utf8.allSatisfy { $0 >= UInt8(ascii: "A") && $0 <= UInt8(ascii: "Z") }
    }

    /// Parse `-?digits[.digits]` into its minor-unit integer and scale, exactly
    /// (integer arithmetic only). Nil when malformed or out of Int64 range.
    static func parseDecimal(_ value: String) -> (minor: Int64, scale: Int)? {
        var text = Substring(value)
        var negative = false
        if text.first == "-" {
            negative = true
            text = text.dropFirst()
        }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 1 || parts.count == 2 else { return nil }
        let whole = parts[0]
        let fraction = parts.count == 2 ? parts[1] : ""
        guard !whole.isEmpty, parts.count == 1 || !fraction.isEmpty else { return nil }
        let digits = whole + fraction
        guard digits.utf8.allSatisfy({ $0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "9") }) else { return nil }
        guard let magnitude = Int64(digits) else { return nil }
        return (negative ? -magnitude : magnitude, fraction.count)
    }
}
