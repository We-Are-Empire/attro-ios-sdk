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

    /// ID of the organization (RideDesk tenant)
    public let orgId: String

    /// Short tracking code from the link
    public let trackingCode: String

    /// How the attribution was matched (nil for Universal Links)
    public let matchMethod: MatchMethod?

    /// How the device was matched for deferred attribution
    public enum MatchMethod: String, Codable, Sendable {
        /// Matched by IP address and User-Agent (most accurate)
        case ipUserAgent = "ip_ua"
        /// Matched by IP address only
        case ipOnly = "ip_exact"
        /// Attributed directly via Universal Link
        case universalLink = "universal_link"
    }

    public init(
        clickId: String,
        affiliateId: String,
        offerId: String,
        orgId: String,
        trackingCode: String,
        matchMethod: MatchMethod? = nil
    ) {
        self.clickId = clickId
        self.affiliateId = affiliateId
        self.offerId = offerId
        self.orgId = orgId
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
    let attribution: AttributionData?
    let subscriberAttributes: [String: String]?

    struct AttributionData: Codable {
        let affiliateId: String
        let offerId: String
        let orgId: String
        let clickId: String
        let trackingCode: String
    }
}
