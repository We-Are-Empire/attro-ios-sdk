import Foundation
import AttroSDK
import RevenueCat

extension Attro {

    /// Apply attribution data to RevenueCat subscriber attributes
    ///
    /// Call this after receiving attribution to ensure RevenueCat
    /// includes the affiliate data in purchase webhooks.
    ///
    /// ## Required ordering
    ///
    /// RevenueCat **must** be configured (`Purchases.configure(...)`) *before*
    /// this is called. `Purchases.shared` is a precondition failure if
    /// `configure` has not run, so this method first checks
    /// `Purchases.isConfigured`: if RevenueCat is not configured it is a no-op
    /// (logged), never a crash. Configure RevenueCat at app launch — typically
    /// in the same place you call `Attro.configure(...)` — so this is safe by the
    /// time you have attribution.
    ///
    /// - Parameter attribution: The attribution data to apply
    /// - Returns: `true` if the attributes were applied, `false` if RevenueCat
    ///   was not configured (no-op).
    ///
    /// ## Example
    ///
    /// ```swift
    /// // RevenueCat must be configured first.
    /// Purchases.configure(withAPIKey: "appl_xxx")
    ///
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
    @discardableResult
    public static func applyToRevenueCat(_ attribution: AttroSDK.Attribution) -> Bool {
        // Guard against the precondition crash in `Purchases.shared`: if an
        // integrator applies attribution before configuring RevenueCat, no-op
        // and log instead of bringing down the host app. See the required
        // ordering above.
        guard Purchases.isConfigured else {
            AttroLog.error(
                "applyToRevenueCat called before Purchases.configure(); skipping. "
                + "Configure RevenueCat at launch before applying attribution."
            )
            return false
        }

        let formatter = ISO8601DateFormatter()
        let now = formatter.string(from: Date())

        Purchases.shared.attribution.setAttributes([
            "$rd_click_id": attribution.clickId,
            "$rd_affiliate_id": attribution.affiliateId,
            "$rd_offer_id": attribution.offerId,
            // The backend webhook reads `$rd_project_id`. `$rd_org_id` is kept
            // transitionally so older backend deployments still receive a value.
            "$rd_project_id": attribution.projectId,
            "$rd_org_id": attribution.projectId,
            "$rd_tracking_code": attribution.trackingCode,
            "$rd_attributed_at": now
        ])
        return true
    }

    /// Apply stored attribution to RevenueCat
    ///
    /// Convenience method that applies any previously stored attribution.
    /// Does nothing if no attribution is stored or if RevenueCat is not yet
    /// configured (see `applyToRevenueCat(_:)` ordering requirements).
    ///
    /// - Returns: `true` if stored attribution existed and was applied.
    @discardableResult
    public static func applyStoredAttributionToRevenueCat() async -> Bool {
        if let attribution = await getStoredAttribution() {
            return applyToRevenueCat(attribution)
        }
        return false
    }
}
