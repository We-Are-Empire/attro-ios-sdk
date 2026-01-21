import Foundation

/// Parser for Attro Universal Links
enum URLParser {

    /// Known Attro hosts
    private static let knownHosts = [
        "get-attro.com",
        "get-attro.com",
        "www.get-attro.com"
    ]

    /// Parse a Universal Link URL into Attribution data
    ///
    /// Supported URL formats:
    /// - `https://get-attro.com/r/{code}?click={id}&aff={id}&offer={id}&org={id}`
    /// - `https://get-attro.com/app/track?click={id}&aff={id}&offer={id}&org={id}&code={code}`
    ///
    /// - Parameter url: The Universal Link URL to parse
    /// - Parameter allowedHosts: Additional hosts to allow (for custom domains)
    /// - Returns: Attribution data if the URL is valid, nil otherwise
    static func parse(_ url: URL, allowedHosts: [String] = []) -> Attribution? {
        guard let host = url.host,
              knownHosts.contains(host) || allowedHosts.contains(host) else {
            return nil
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            return nil
        }

        // Extract query parameters
        var params: [String: String] = [:]
        components.queryItems?.forEach { item in
            if let value = item.value {
                params[item.name] = value
            }
        }

        // Try to get all required parameters
        // Parameter names: click (or click_id), aff (or affiliate_id), offer (or offer_id), org (or org_id), code
        let clickId = params["click"] ?? params["click_id"]
        let affiliateId = params["aff"] ?? params["affiliate_id"]
        let offerId = params["offer"] ?? params["offer_id"]
        let orgId = params["org"] ?? params["org_id"]
        let trackingCode = params["code"] ?? extractCodeFromPath(url.path)

        // Validate we have all required parameters
        guard let clickId = clickId,
              let affiliateId = affiliateId,
              let offerId = offerId,
              let orgId = orgId,
              let trackingCode = trackingCode else {
            return nil
        }

        return Attribution(
            clickId: clickId,
            affiliateId: affiliateId,
            offerId: offerId,
            orgId: orgId,
            trackingCode: trackingCode,
            matchMethod: .universalLink
        )
    }

    /// Extract tracking code from URL path
    /// e.g., "/r/abc12345" -> "abc12345"
    private static func extractCodeFromPath(_ path: String) -> String? {
        let components = path.split(separator: "/")

        // Look for /r/{code} pattern
        if components.count >= 2 && components[0] == "r" {
            return String(components[1])
        }

        return nil
    }

    /// Check if a URL is an Attro Universal Link
    static func isAttroLink(_ url: URL, allowedHosts: [String] = []) -> Bool {
        guard let host = url.host else { return false }

        let isKnownHost = knownHosts.contains(host) || allowedHosts.contains(host)
        let isTrackingPath = url.path.hasPrefix("/r/") || url.path.hasPrefix("/app/track")

        return isKnownHost && isTrackingPath
    }
}
