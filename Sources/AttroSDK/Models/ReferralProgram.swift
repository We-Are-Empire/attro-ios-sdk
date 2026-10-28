import Foundation

/// A user's peer-to-peer referral-program info, returned by `/api/app/referral/me`.
///
/// This is the in-app "invite a friend" surface: the caller gets a shareable
/// referral `code` + `shareUrl` (render a QR from `shareUrl` on-device) and live
/// P2P stats. Distinct from ``AffiliateInfo`` (the `/api/app/my-affiliate`
/// affiliate profile): this one is scoped to the project's referral *program*
/// and reports referral completion/pending counts and token rewards.
public struct ReferralProgramInfo: Codable, Sendable, Equatable {
    /// The user's referral code (e.g., "abc12345").
    public let code: String

    /// The shareable URL for the code: `<program share_base_url>/<code>` when
    /// the program sets a share base URL, otherwise the project's Universal
    /// Link (`https://<platform>/a/<public_slug>/<code>`). Render a QR from THIS
    /// value on-device; never build links by hand.
    public let shareUrl: String

    /// Live referral stats for the user.
    public let stats: Stats

    /// The project's default `subscription_credit` reward: how earned tokens
    /// convert into value (e.g. a percentage off the next subscription payment).
    /// `nil` when the project has no (unambiguous) subscription-credit reward.
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
        /// The user's CURRENT spendable token balance (earned minus redeemed):
        /// render this as "N credits".
        public let tokenBalance: Int?
    }

    /// The reward a token redeems into, advertised so the app can describe the
    /// credit ("each credit = 20% off a month") without hardcoding its value.
    public struct DefaultReward: Codable, Sendable, Equatable {
        public let id: String
        public let name: String
        /// Tokens one redemption spends.
        public let tokenCost: Int
        /// The credit's configuration, when set.
        public let fulfillmentData: FulfillmentData?

        enum CodingKeys: String, CodingKey {
            case id, name, tokenCost, fulfillmentData
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            name = try container.decode(String.self, forKey: .name)
            tokenCost = try container.decode(Int.self, forKey: .tokenCost)
            // `fulfillment_data` is free-form tenant JSON: a shape this SDK does
            // not know must not fail the whole response.
            fulfillmentData = try? container.decodeIfPresent(FulfillmentData.self, forKey: .fulfillmentData)
        }
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

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            discountPercent = try? container.decodeIfPresent(Int.self, forKey: .discountPercent)
            applies = try? container.decodeIfPresent(String.self, forKey: .applies)
        }
    }
}

// MARK: - Convenience

extension ReferralProgramInfo {
    /// The share URL as a `URL`, when well-formed.
    public var shareURL: URL? { URL(string: shareUrl) }
}

/// Request body for `POST /api/app/referral/me` and `/api/app/my-affiliate`.
/// The tenant is resolved server-side from the app key and the user from the
/// verified bearer token; the body only names the identity provider that
/// issued the token.
struct ProviderRequest: Encodable {
    let provider: String
}
