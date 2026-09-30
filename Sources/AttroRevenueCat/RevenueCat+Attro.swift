import Foundation
import AttroSDK
import RevenueCat

/// RevenueCat conveniences. Each reads the RevenueCat app user id
/// (`Purchases.shared.appUserID`), calls the matching `Attro` method, and then
/// points RevenueCat at ``Attro/currentAttribution()`` by setting exactly one
/// subscriber attribute, `attro_attribution_id` (contract §4).
///
/// RevenueCat must be configured first (`Purchases.configure(...)`); otherwise
/// these throw ``AttroError/revenueCatNotConfigured`` instead of crashing.
///
/// RevenueCat syncs attributes when it is configured, when the app goes to the
/// background, and when a purchase is made, so an attribute set before the
/// paywall is presented reaches the purchase event.
extension Attro {

    /// ``Attro/handleUniversalLink(_:appUserId:)`` for the RevenueCat app
    /// user, then ``applyCurrentAttributionToRevenueCat()``.
    @discardableResult
    public static func handleUniversalLink(_ url: URL) async throws -> AttributionOutcome? {
        let outcome = try await handleUniversalLink(url, appUserId: try revenueCatAppUserId())
        if outcome != nil { await applyCurrentAttributionToRevenueCat() }
        return outcome
    }

    /// ``Attro/submitCode(_:appUserId:publicSlug:)`` for the RevenueCat app
    /// user, then ``applyCurrentAttributionToRevenueCat()``.
    public static func submitCode(_ code: String, publicSlug: String? = nil) async throws -> AttributionOutcome {
        let outcome = try await submitCode(code, appUserId: try revenueCatAppUserId(), publicSlug: publicSlug)
        await applyCurrentAttributionToRevenueCat()
        return outcome
    }

    /// ``Attro/matchInstall(appUserId:)`` for the RevenueCat app user, then
    /// ``applyCurrentAttributionToRevenueCat()``. A no-op unless probabilistic
    /// matching is configured.
    @discardableResult
    public static func matchInstall() async throws -> AttributionOutcome? {
        let outcome = try await matchInstall(appUserId: try revenueCatAppUserId())
        if outcome != nil { await applyCurrentAttributionToRevenueCat() }
        return outcome
    }

    /// Set `attro_attribution_id` from `result` on RevenueCat.
    ///
    /// - Returns: false (a logged no-op) when RevenueCat is not configured.
    @discardableResult
    public static func applyToRevenueCat(_ result: AttributionResult) -> Bool {
        guard Purchases.isConfigured else {
            AttroLog.error(
                "applyToRevenueCat called before Purchases.configure(); skipping. "
                + "Configure RevenueCat at launch before applying attribution."
            )
            return false
        }
        // Exactly one attribute, and only keys RevenueCat accepts (no `$`).
        let attributes = result.subscriberAttributes.filter { SubscriberAttributes.isValidKey($0.key) }
        Purchases.shared.attribution.setAttributes(attributes)
        return true
    }

    /// Set `attro_attribution_id` from ``Attro/currentAttribution()``. Call it
    /// before presenting the paywall, and after
    /// ``Attro/retryPendingAttributions()``.
    ///
    /// - Returns: true when there was an attribution and it was applied.
    @discardableResult
    public static func applyCurrentAttributionToRevenueCat() async -> Bool {
        guard let current = await currentAttribution() else { return false }
        return applyToRevenueCat(current)
    }

    private static func revenueCatAppUserId() throws -> String {
        guard Purchases.isConfigured else { throw AttroError.revenueCatNotConfigured }
        return Purchases.shared.appUserID
    }
}
