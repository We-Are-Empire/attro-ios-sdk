import Foundation
import os

/// Lightweight internal logging for the Attro SDK.
///
/// The SDK has no UI and runs on the integrator's app, so failures that we
/// deliberately swallow (e.g. a fire-and-forget storage write, or a no-op when
/// RevenueCat is not configured) must still be *observable* — silently dropping
/// them is the footgun this replaces. We log to the unified logging system under
/// a stable subsystem/category so integrators can filter on it in Console /
/// `log stream --predicate 'subsystem == "com.attro.sdk"'`.
public enum AttroLog {
    private static let logger = Logger(subsystem: "com.attro.sdk", category: "AttroSDK")

    /// Informational events (expected no-ops worth surfacing during debugging).
    public static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    /// Recoverable problems the integrator should know about but that do not
    /// throw (e.g. a background storage write failed, or attribution was applied
    /// before RevenueCat was configured).
    public static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}
