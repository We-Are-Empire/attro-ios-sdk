import Foundation

/// The RevenueCat subscriber attribute contract (contract §4).
///
/// The app sets exactly one subscriber attribute, `attro_attribution_id`, whose
/// value is the id of the server-side attribution row from the last attributed
/// answer. The attribute is only a pointer: the server decides which affiliate
/// and offer the row credits, and changing the attribute later cannot move a
/// subscription to another affiliate.
public enum SubscriberAttributes {
    /// The one attribute key Attro reads.
    public static let attributionIdKey = "attro_attribution_id"

    /// Whether `key` follows RevenueCat's rules for custom attribute keys: no
    /// `$` prefix (reserved by RevenueCat), only letters, digits, `-` and `_`,
    /// and at most 40 characters.
    public static func isValidKey(_ key: String) -> Bool {
        guard !key.isEmpty, key.utf8.count <= 40 else { return false }
        return key.utf8.allSatisfy { byte in
            (byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z"))
                || (byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z"))
                || (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9"))
                || byte == UInt8(ascii: "-")
                || byte == UInt8(ascii: "_")
        }
    }
}

/// How an attribution was made. Deterministic sources (`universalLink`,
/// `code`) always win over `probabilistic`.
public enum AttributionSource: Sendable, Hashable, Codable, CustomStringConvertible {
    /// The app was opened by a tenant Universal Link.
    case universalLink
    /// The user typed an affiliate code.
    case code
    /// The opt-in IP + User-Agent install match.
    case probabilistic
    /// A source this SDK version does not know yet.
    case other(String)

    public init(rawValue: String) {
        switch rawValue {
        case "universal_link": self = .universalLink
        case "code": self = .code
        case "probabilistic": self = .probabilistic
        default: self = .other(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .universalLink: return "universal_link"
        case .code: return "code"
        case .probabilistic: return "probabilistic"
        case .other(let value): return value
        }
    }

    /// Whether this source is exact (not a probabilistic guess).
    public var isDeterministic: Bool {
        switch self {
        case .universalLink, .code: return true
        case .probabilistic, .other: return false
        }
    }

    public var description: String { rawValue }

    public init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Why the server did not attribute (contract §3). Always a `200` answer.
public enum NotAttributedReason: Sendable, Hashable, Codable, CustomStringConvertible {
    /// The link's code is unknown, dead, or belongs to another project.
    case unknownLink
    /// The typed code is unknown, dead, or belongs to another project.
    case unknownCode
    /// The click was rejected by the project's fraud rules.
    case rejected
    /// The probabilistic match found no (unambiguous) click.
    case noMatch
    /// The project has not opted in to probabilistic matching.
    case notEnabled
    /// A reason this SDK version does not know yet.
    case other(String)

    public init(rawValue: String) {
        switch rawValue {
        case "unknown_link": self = .unknownLink
        case "unknown_code": self = .unknownCode
        case "rejected": self = .rejected
        case "no_match": self = .noMatch
        case "not_enabled": self = .notEnabled
        default: self = .other(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .unknownLink: return "unknown_link"
        case .unknownCode: return "unknown_code"
        case .rejected: return "rejected"
        case .noMatch: return "no_match"
        case .notEnabled: return "not_enabled"
        case .other(let value): return value
        }
    }

    public var description: String { rawValue }

    public init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// A server-side attribution the app points RevenueCat at.
///
/// The SDK never learns (or sends) which affiliate, offer or project an
/// attribution credits: the server decided that and stored it in the row this
/// id names.
public struct AttributionResult: Codable, Sendable, Hashable {
    /// The `app_attributions` row id.
    public let attributionId: String

    /// How the server attributed.
    public let source: AttributionSource

    /// When the SDK received the answer (device clock; informational only, the
    /// server measures attribution windows from its own time).
    public let receivedAt: Date

    public init(attributionId: String, source: AttributionSource, receivedAt: Date = Date()) {
        self.attributionId = attributionId
        self.source = source
        self.receivedAt = receivedAt
    }

    /// Exactly the RevenueCat subscriber attributes to set for this
    /// attribution: `["attro_attribution_id": attributionId]`.
    public var subscriberAttributes: [String: String] {
        [SubscriberAttributes.attributionIdKey: attributionId]
    }
}

/// The answer to one attribution attempt.
public enum AttributionOutcome: Sendable, Hashable {
    /// The server bound this install and app user to an attribution row.
    case attributed(AttributionResult)
    /// The server answered, but did not attribute.
    case notAttributed(NotAttributedReason)

    /// The result when attributed, nil otherwise.
    public var result: AttributionResult? {
        if case .attributed(let result) = self { return result }
        return nil
    }
}
