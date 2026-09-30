import Foundation

/// The signed-in user's affiliate profile, link and stats, returned by
/// `POST /api/ios/my-affiliate` (contract §6, refer-a-friend).
///
/// The server gets or creates the user's (internal) affiliate. Money is exact:
/// `stats.earnings` is a ``Money`` object in the program currency, never a
/// floating-point number.
public struct AffiliateInfo: Codable, Sendable, Equatable {
    /// The affiliate's profile.
    public let affiliate: Affiliate

    /// The affiliate's primary tracking link.
    public let trackingLink: TrackingLink

    /// Performance statistics.
    public let stats: Stats

    /// Pre-formatted content for the share sheet.
    public let shareContent: ShareContent

    public struct Affiliate: Codable, Sendable, Equatable {
        public let id: String
        /// `"internal"` (app user) or `"external"` (partner).
        public let type: String
        /// Account status, e.g. `"active"`.
        public let status: String
        /// ISO 8601 creation time.
        public let createdAt: String
    }

    public struct TrackingLink: Codable, Sendable, Equatable {
        public let id: String
        /// The tracking link code.
        public let code: String
        /// The link to share: the project's Universal Link
        /// (`https://<platform>/a/<public_slug>/<code>`). Never build it by hand.
        public let url: String
        /// The link's offer, when the server includes it.
        public let offer: Offer?

        public struct Offer: Codable, Sendable, Equatable {
            public let id: String
            public let name: String?
            public let url: String?
        }
    }

    public struct Stats: Codable, Sendable, Equatable {
        public let clicks: Int
        public let conversions: Conversions
        /// Earned reward value, exact, in the program currency.
        public let earnings: Money
        /// The server's display string for `earnings`.
        public let earningsFormatted: String
        public let tokens: Tokens

        public struct Conversions: Codable, Sendable, Equatable {
            public let total: Int
            public let approved: Int
            public let pending: Int
        }

        public struct Tokens: Codable, Sendable, Equatable {
            public let balance: Int
            public let lifetimeEarned: Int
        }
    }

    public struct ShareContent: Codable, Sendable, Equatable {
        public let text: String
        public let url: String
    }
}

extension AffiliateInfo {
    /// The referral URL, when well-formed.
    public var referralURL: URL? { URL(string: trackingLink.url) }
}
