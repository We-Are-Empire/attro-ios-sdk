import Foundation

/// Complete referral information for an affiliate
///
/// Contains the affiliate's profile, tracking link, statistics,
/// and pre-formatted content for sharing.
public struct ReferralInfo: Codable, Sendable {
    /// The affiliate's profile
    public let affiliate: Affiliate

    /// The affiliate's primary tracking link
    public let trackingLink: TrackingLink

    /// Performance statistics
    public let stats: Stats

    /// Pre-formatted content for sharing
    public let shareContent: ShareContent

    // MARK: - Nested Types

    /// Affiliate profile information
    public struct Affiliate: Codable, Sendable {
        /// Unique identifier
        public let id: String

        /// Affiliate type: "internal" (app user) or "external" (partner)
        public let type: String

        /// Account status: "active", "pending", "suspended"
        public let status: String

        /// When the affiliate was created
        public let createdAt: String
    }

    /// Tracking link for referrals
    public struct TrackingLink: Codable, Sendable {
        /// Unique identifier
        public let id: String

        /// Short tracking code (e.g., "abc12345")
        public let code: String

        /// Full URL for sharing (e.g., "https://get-attro.com/r/abc12345")
        public let url: String

        /// Associated offer (optional)
        public let offer: Offer?

        public struct Offer: Codable, Sendable {
            public let id: String
            public let name: String
            public let url: String
        }
    }

    /// Performance statistics
    public struct Stats: Codable, Sendable {
        /// Total clicks on tracking links
        public let clicks: Int

        /// Conversion breakdown
        public let conversions: Conversions

        /// Total monetary earnings (for external affiliates)
        public let earnings: Double

        /// Token balance (for internal affiliates)
        public let tokens: Tokens

        public struct Conversions: Codable, Sendable {
            /// Total conversions (all statuses)
            public let total: Int
            /// Approved conversions
            public let approved: Int
            /// Pending approval
            public let pending: Int
        }

        public struct Tokens: Codable, Sendable {
            /// Current token balance
            public let balance: Int
            /// Total tokens ever earned
            public let lifetimeEarned: Int
        }
    }

    /// Pre-formatted content for sharing
    public struct ShareContent: Codable, Sendable {
        /// Suggested text to share with the link
        public let text: String
        /// The referral URL to share
        public let url: String
    }
}

// MARK: - Convenience

extension ReferralInfo {
    /// The referral URL for easy access
    public var referralURL: URL? {
        URL(string: trackingLink.url)
    }

    /// Items suitable for UIActivityViewController
    public var shareItems: [Any] {
        var items: [Any] = [shareContent.text]
        if let url = referralURL {
            items.append(url)
        }
        return items
    }
}
