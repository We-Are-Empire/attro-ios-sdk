import Foundation

/// A user's peer-to-peer referral-program info, returned by `/api/ios/referral/me`.
///
/// This is the invisible in-app "invite a friend" surface: the caller gets a
/// shareable referral `code` + `shareUrl` (render a QR from `shareUrl` on-device)
/// and live P2P stats. Distinct from ``ReferralInfo`` (the older `/my-affiliate`
/// affiliate profile) — this one is scoped to the project's referral *program*
/// and reports referral completion/pending counts and token rewards.
public struct ReferralProgramInfo: Codable, Sendable, Equatable {
    /// The user's referral code (e.g., "abc12345").
    public let code: String

    /// The shareable URL for the code — `<program share_base_url>/<code>`, as
    /// configured per referral program in Attro. Render a QR from THIS value
    /// on-device.
    public let shareUrl: String

    /// Live referral stats for the user.
    public let stats: Stats

    /// The project's default `subscription_credit` reward — how earned tokens
    /// convert into value (e.g. a percentage off the next subscription payment).
    /// `nil` when the project has no (unambiguous) subscription-credit reward
    /// configured, or when talking to a backend that predates the field.
    public let defaultReward: DefaultReward?

    public struct Stats: Codable, Sendable, Equatable {
        /// Referrals that reached first-paid (referrer token awarded).
        public let completed: Int
        /// Referrals attributed but not yet completed (trial / pre-first-paid).
        public let pending: Int
        /// Tokens the user has actually earned from completed referrals.
        public let tokensEarned: Int
        /// Tokens withheld pending completion of `pending` referrals.
        public let tokensPending: Int
        /// The user's CURRENT spendable token balance (earned minus redeemed) —
        /// render this as "N credits". Optional: absent on older backends.
        public let tokenBalance: Int?
    }

    /// The reward a token redeems into, advertised so the app can describe the
    /// credit ("each credit = 20% off a month") without hardcoding its value.
    public struct DefaultReward: Codable, Sendable, Equatable {
        public let id: String
        public let name: String
        /// Tokens one redemption spends (currently 1).
        public let tokenCost: Int
        /// The credit's configuration, when set.
        public let fulfillmentData: FulfillmentData?
    }

    /// Known keys of the reward's `fulfillment_data` JSON. The server stores
    /// arbitrary JSON here; unknown keys are ignored. The JSON's own keys are
    /// snake_case (raw config), unlike the camelCase response envelope.
    public struct FulfillmentData: Codable, Sendable, Equatable {
        /// Percentage off one payment per credit (e.g. 20).
        public let discountPercent: Int?
        /// What the credit applies to (e.g. "next_invoice").
        public let applies: String?

        enum CodingKeys: String, CodingKey {
            case discountPercent = "discount_percent"
            case applies
        }
    }
}

// MARK: - Convenience

extension ReferralProgramInfo {
    /// The share URL as a `URL`, when well-formed.
    public var shareURL: URL? { URL(string: shareUrl) }
}

/// Request body for `POST /api/ios/referral/me`. The tenant (org/project) is
/// resolved server-side from the per-project app key and the affiliate identity
/// from the verified bearer token — neither is ever taken from the body. The
/// body only names the identity provider that issued the bearer token.
struct ReferralProgramRequest: Encodable {
    let provider: String
}
