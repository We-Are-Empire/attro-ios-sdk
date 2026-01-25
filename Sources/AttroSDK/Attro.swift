import Foundation

/// Attro SDK for iOS affiliate tracking - v1.0
///
/// Use this SDK to:
/// - Check for deferred attribution on first app launch
/// - Parse Universal Links for direct attribution
/// - Get referral info and share links for logged-in users
///
/// ## Quick Start
///
/// ```swift
/// // 1. Configure on app launch
/// Attro.configure(organizationSlug: "ride-ios")
///
/// // 2. Check deferred attribution
/// if let attribution = try await Attro.checkAttribution() {
///     Attro.applyToRevenueCat(attribution)
/// }
///
/// // 3. Handle Universal Links
/// if let attribution = Attro.parseUniversalLink(url) {
///     Attro.storeAttribution(attribution)
///     Attro.applyToRevenueCat(attribution)
/// }
///
/// // 4. Get referral info for logged-in users
/// let referral = try await Attro.getMyReferral(userId: user.id)
/// ```
public enum Attro {

    // MARK: - Configuration

    private static var _config: Configuration?
    private static let storage = AttroStorage()
    private static var apiClient: APIClient?

    /// SDK configuration
    public struct Configuration: Sendable {
        /// Organization slug (e.g., "ride-ios")
        public let organizationSlug: String

        /// Base URL for the Attro API
        public let baseURL: URL

        /// Additional hosts to allow for Universal Links
        public let allowedHosts: [String]

        public init(
            organizationSlug: String,
            baseURL: URL = URL(string: "https://get-attro.com")!,
            allowedHosts: [String] = []
        ) {
            self.organizationSlug = organizationSlug
            self.baseURL = baseURL
            self.allowedHosts = allowedHosts
        }
    }

    /// Configure the SDK
    ///
    /// Call this once on app launch, typically in your App's init or AppDelegate.
    ///
    /// - Parameter configuration: SDK configuration
    public static func configure(_ configuration: Configuration) {
        _config = configuration
        apiClient = APIClient(baseURL: configuration.baseURL)
        Task {
            await storage.setConfiguredAt(Date())
        }
    }

    /// Configure the SDK with default settings
    ///
    /// - Parameter organizationSlug: Your organization's slug (e.g., "ride-ios")
    /// - Parameter baseURL: Optional custom base URL (defaults to production)
    public static func configure(
        organizationSlug: String,
        baseURL: URL = URL(string: "https://get-attro.com")!
    ) {
        configure(Configuration(organizationSlug: organizationSlug, baseURL: baseURL))
    }

    /// Current configuration (nil if not configured)
    public static var configuration: Configuration? { _config }

    /// Whether the SDK has been configured
    public static var isConfigured: Bool { _config != nil }

    // MARK: - Deferred Attribution

    /// Check for deferred attribution on first app launch
    ///
    /// This method:
    /// 1. Collects device fingerprint information
    /// 2. Calls the Attro API to check for a matching click
    /// 3. Returns attribution data if a match is found
    ///
    /// Only runs once per install. Subsequent calls return nil without making API calls.
    ///
    /// - Returns: Attribution data if a match was found, nil otherwise
    /// - Throws: `AttroError` if not configured or network error occurs
    @MainActor
    public static func checkAttribution() async throws -> Attribution? {
        guard apiClient != nil else {
            throw AttroError.notConfigured
        }

        // Check if already checked
        if await storage.attributionChecked {
            // Return stored attribution if available
            return await storage.storedAttribution
        }

        // Collect device info
        let deviceInfo = DeviceInfo.current
        let request = MatchRequest(deviceInfo: deviceInfo)

        // Call API
        let response: MatchResponse = try await apiClient!.post("/api/ios/match", body: request)

        // Mark as checked
        await storage.setAttributionChecked(true)

        // If matched, create and store attribution
        guard response.matched, let data = response.attribution else {
            return nil
        }

        let matchMethod: Attribution.MatchMethod
        switch response.matchMethod {
        case "ip_ua": matchMethod = .ipUserAgent
        case "ip_exact": matchMethod = .ipOnly
        default: matchMethod = .ipUserAgent
        }

        let attribution = Attribution(
            clickId: data.clickId,
            affiliateId: data.affiliateId,
            offerId: data.offerId,
            orgId: data.orgId,
            trackingCode: data.trackingCode,
            matchMethod: matchMethod
        )

        // Store for future reference
        await storage.setStoredAttribution(attribution)

        return attribution
    }

    // MARK: - Universal Links

    /// Parse a Universal Link URL into attribution data
    ///
    /// Call this when your app receives a Universal Link to extract attribution.
    ///
    /// - Parameter url: The Universal Link URL
    /// - Returns: Attribution data if the URL is valid, nil otherwise
    public static func parseUniversalLink(_ url: URL) -> Attribution? {
        let allowedHosts = _config?.allowedHosts ?? []
        return URLParser.parse(url, allowedHosts: allowedHosts)
    }

    /// Check if a URL is an Attro Universal Link
    ///
    /// - Parameter url: The URL to check
    /// - Returns: true if this is an Attro link that should be handled
    public static func isAttroLink(_ url: URL) -> Bool {
        let allowedHosts = _config?.allowedHosts ?? []
        return URLParser.isAttroLink(url, allowedHosts: allowedHosts)
    }

    // MARK: - Attribution Storage

    /// Store attribution data locally
    ///
    /// Use this to persist attribution from Universal Links for later use.
    ///
    /// - Parameter attribution: The attribution data to store
    public static func storeAttribution(_ attribution: Attribution) {
        Task {
            await storage.setStoredAttribution(attribution)
        }
    }

    /// Get previously stored attribution data
    ///
    /// - Returns: Stored attribution if available
    public static func getStoredAttribution() async -> Attribution? {
        await storage.storedAttribution
    }

    // MARK: - Refer-a-Friend

    /// Get referral information for a logged-in user
    ///
    /// This returns the user's affiliate profile, tracking link, and stats.
    /// If the user doesn't have an affiliate record, one is created automatically.
    ///
    /// - Parameter userId: The user's Supabase user ID
    /// - Parameter orgSlug: Optional organization slug (uses configured default)
    /// - Returns: Complete referral information
    /// - Throws: `AttroError` if not configured or request fails
    public static func getMyReferral(
        userId: String,
        orgSlug: String? = nil
    ) async throws -> ReferralInfo {
        guard let client = apiClient, let config = _config else {
            throw AttroError.notConfigured
        }

        let request = MyAffiliateRequest(
            rideUserId: userId,
            orgSlug: orgSlug ?? config.organizationSlug
        )

        return try await client.post("/api/ios/my-affiliate", body: request)
    }

    // MARK: - Testing / Debug

    /// Reset all stored SDK data
    ///
    /// Use this for testing to reset the attribution checked flag
    /// and clear any stored attribution data.
    public static func reset() async {
        await storage.reset()
    }
}
