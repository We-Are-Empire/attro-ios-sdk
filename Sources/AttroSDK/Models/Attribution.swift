import Foundation

/// Attribution data from a tracking link click
///
/// This contains the affiliate and offer information needed to attribute
/// a conversion to the correct affiliate.
public struct Attribution: Codable, Sendable, Equatable {
    /// Unique identifier for the original click
    public let clickId: String

    /// ID of the affiliate who shared the link
    public let affiliateId: String

    /// ID of the offer being promoted
    public let offerId: String

    /// ID of the project (Attro tenant scope) the affiliate/offer belong to.
    ///
    /// This is the value the backend persists on conversions and reads from the
    /// `$rd_project_id` RevenueCat subscriber attribute. It is distinct from the
    /// organization id.
    public let projectId: String

    /// Short tracking code from the link
    public let trackingCode: String

    /// How the attribution was matched (nil for Universal Links)
    public let matchMethod: MatchMethod?

    /// How the device was matched for deferred attribution.
    ///
    /// The raw values mirror the strings emitted by the backend matcher
    /// (`/api/ios/match`). Map directly from the response string and avoid a
    /// silent default so new backend methods are not misreported.
    public enum MatchMethod: String, Codable, Sendable {
        /// IP + full User-Agent exact match (highest confidence)
        case ipUserAgentExact = "ip_ua_exact"
        /// IP + partial User-Agent match
        case ipUserAgentPartial = "ip_ua_partial"
        /// IP-only match (no User-Agent agreement)
        case ipOnly = "ip_only"
        /// Legacy IP + User-Agent match (pre-v2 matcher)
        case ipUserAgent = "ip_ua"
        /// Legacy IP-only / exact match (pre-v2 matcher)
        case ipExact = "ip_exact"
        /// Attributed directly via Universal Link
        case universalLink = "universal_link"
    }

    public init(
        clickId: String,
        affiliateId: String,
        offerId: String,
        projectId: String,
        trackingCode: String,
        matchMethod: MatchMethod? = nil
    ) {
        self.clickId = clickId
        self.affiliateId = affiliateId
        self.offerId = offerId
        self.projectId = projectId
        self.trackingCode = trackingCode
        self.matchMethod = matchMethod
    }
}

// MARK: - API Response Types

/// Response from the deferred attribution matching API
struct MatchResponse: Codable {
    let matched: Bool
    let matchMethod: String?
    let message: String?
    let confidenceScore: Double?
    let attribution: AttributionData?
    let subscriberAttributes: [String: String]?

    struct AttributionData: Codable {
        let affiliateId: String
        let offerId: String
        /// Project id returned by the backend. The backend match response uses
        /// the key `projectId`; `orgId` is accepted as a transitional fallback.
        let projectId: String?
        let orgId: String?
        let clickId: String
        let trackingCode: String

        /// The resolved project id, preferring `projectId` and falling back to
        /// the legacy `orgId` key.
        var resolvedProjectId: String? {
            projectId ?? orgId
        }
    }
}
