import Foundation
import AttroSDK
import RevenueCat

extension Attro {

    /// Apply attribution data to RevenueCat subscriber attributes
    ///
    /// Call this after receiving attribution to ensure RevenueCat
    /// includes the affiliate data in purchase webhooks.
    ///
    /// - Parameter attribution: The attribution data to apply
    ///
    /// ## Example
    ///
    /// ```swift
    /// // After checking deferred attribution
    /// if let attribution = try await Attro.checkAttribution() {
    ///     Attro.applyToRevenueCat(attribution)
    /// }
    ///
    /// // After parsing a Universal Link
    /// if let attribution = Attro.parseUniversalLink(url) {
    ///     Attro.storeAttribution(attribution)
    ///     Attro.applyToRevenueCat(attribution)
    /// }
    /// ```
    public static func applyToRevenueCat(_ attribution: AttroSDK.Attribution) {
        let formatter = ISO8601DateFormatter()
        let now = formatter.string(from: Date())

        Purchases.shared.attribution.setAttributes([
            "$rd_click_id": attribution.clickId,
            "$rd_affiliate_id": attribution.affiliateId,
            "$rd_offer_id": attribution.offerId,
            "$rd_org_id": attribution.orgId,
            "$rd_tracking_code": attribution.trackingCode,
            "$rd_attributed_at": now
        ])
    }

    /// Apply stored attribution to RevenueCat
    ///
    /// Convenience method that applies any previously stored attribution.
    /// Does nothing if no attribution is stored.
    public static func applyStoredAttributionToRevenueCat() async {
        if let attribution = await getStoredAttribution() {
            applyToRevenueCat(attribution)
        }
    }
}
