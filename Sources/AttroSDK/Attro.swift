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

    private static let storage = AttroStorage()

    /// The shared configuration and API client are mutable global state that is
    /// written by `configure()` and read from several isolation domains
    /// (`@MainActor` for `checkAttribution`, non-isolated for
    /// `parseUniversalLink`/`storeAttribution`). Guard every access behind a lock
    /// so concurrent `configure()` / first-use never race on the raw statics —
    /// which strict-concurrency builds flag and which could otherwise surface as
    /// a transiently `nil` `apiClient`.
    private static let stateLock = NSLock()
    private nonisolated(unsafe) static var _config: Configuration?
    private nonisolated(unsafe) static var _apiClient: APIClient?

    /// Atomically read the current configuration and API client together so a
    /// caller never observes a half-applied `configure()`.
    private static func currentState() -> (config: Configuration?, client: APIClient?) {
        stateLock.lock()
        defer { stateLock.unlock() }
        return (_config, _apiClient)
    }

    /// SDK configuration
    public struct Configuration: Sendable {
        /// Organization slug (e.g., "ride-ios")
        public let organizationSlug: String

        /// Base URL for the Attro API
        public let baseURL: URL

        /// Additional hosts to allow for Universal Links
        public let allowedHosts: [String]

        /// Server-to-server API key (`x-api-key`) for the P2P referral endpoints
        /// (`/api/ios/referral/*`). Optional — only required if you call
        /// `getReferralProgram`. Provided by Attro; ship it in your app config.
        public let apiKey: String?

        public init(
            organizationSlug: String,
            baseURL: URL = URL(string: "https://get-attro.com")!,
            allowedHosts: [String] = [],
            apiKey: String? = nil
        ) {
            self.organizationSlug = organizationSlug
            self.baseURL = baseURL
            self.allowedHosts = allowedHosts
            self.apiKey = apiKey
        }
    }

    /// Configure the SDK
    ///
    /// Call this once on app launch, typically in your App's init or AppDelegate.
    ///
    /// - Parameter configuration: SDK configuration
    public static func configure(_ configuration: Configuration) {
        let client = APIClient(baseURL: configuration.baseURL)
        stateLock.lock()
        _config = configuration
        _apiClient = client
        stateLock.unlock()
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
    public static var configuration: Configuration? { currentState().config }

    /// Whether the SDK has been configured
    public static var isConfigured: Bool { currentState().config != nil }

    // MARK: - Deferred Attribution

    /// Check for deferred attribution on first app launch
    ///
    /// This method:
    /// 1. Collects device fingerprint information (including the real device
    ///    User-Agent so the backend can match on browser family, not IP alone)
    /// 2. Calls the Attro API to check for a matching click, with bounded retry
    ///    on transient failures
    /// 3. Returns attribution data if a match is found
    ///
    /// Only runs once per install for a *definitive* answer. If the check fails
    /// transiently (offline / 5xx flagged `retryable`), the install is NOT marked
    /// as checked: a durable pending-check flag is persisted so the next launch
    /// retries instead of permanently losing attribution. Call this on every
    /// launch — it is a no-op once a definitive answer has been recorded.
    ///
    /// - Returns: Attribution data if a match was found, nil otherwise
    /// - Throws: `AttroError` if not configured or a (post-retry) network error
    ///   occurs. A thrown retryable error means a retry is durably scheduled.
    @MainActor
    public static func checkAttribution() async throws -> Attribution? {
        guard let client = currentState().client else {
            throw AttroError.notConfigured
        }

        // A definitive answer was already recorded — return any stored
        // attribution without another network call. A still-pending check (from
        // a prior transient failure) does NOT short-circuit here, so it is
        // retried on this launch.
        if await storage.attributionChecked {
            return await storage.storedAttribution
        }

        // Collect device info
        let deviceInfo = DeviceInfo.current
        let request = MatchRequest(deviceInfo: deviceInfo)

        // Call API, sending the real device User-Agent so the backend matcher
        // can award browser-family confidence points instead of degrading to an
        // IP-only match. The APIClient retries transient failures internally.
        let response: MatchResponse
        do {
            response = try await client.post(
                "/api/ios/match",
                body: request,
                userAgent: deviceInfo.userAgent
            )
        } catch let error as AttroError where error.isRetryable {
            // Transient failure after exhausting in-process retries: do NOT mark
            // as checked. Persist a pending-check flag so the next launch retries
            // and attribution is not permanently lost.
            await storage.setPendingCheck(true)
            throw error
        }

        // Definitive answer received (match or genuine no-match): record it so we
        // do not check again, and clear any pending-retry flag.
        await storage.setAttributionChecked(true)
        await storage.setPendingCheck(false)

        // If matched, create and store attribution. A successful match must
        // carry a project id (either the `projectId` key or the legacy `orgId`
        // fallback); without it we cannot attribute downstream, so treat it as
        // no attribution rather than fabricating one.
        guard response.matched,
              let data = response.attribution,
              let projectId = data.resolvedProjectId else {
            return nil
        }

        // Map the backend match-method string directly from its raw value so
        // every method (ip_ua_exact / ip_ua_partial / ip_only and the legacy
        // ip_ua / ip_exact) is preserved instead of collapsing to a default.
        let matchMethod = response.matchMethod.flatMap(Attribution.MatchMethod.init(rawValue:))

        let attribution = Attribution(
            clickId: data.clickId,
            affiliateId: data.affiliateId,
            offerId: data.offerId,
            projectId: projectId,
            trackingCode: data.trackingCode,
            matchMethod: matchMethod
        )

        // Store for future reference. The encode is on a small, known-Codable
        // value so a failure is not expected, but if it ever happens we surface
        // it rather than silently returning attribution that was never persisted.
        do {
            try await storage.setStoredAttribution(attribution)
        } catch {
            AttroLog.error("Failed to persist matched attribution: \(error.localizedDescription)")
        }

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
        let allowedHosts = currentState().config?.allowedHosts ?? []
        return URLParser.parse(url, allowedHosts: allowedHosts)
    }

    /// Check if a URL is an Attro Universal Link
    ///
    /// - Parameter url: The URL to check
    /// - Returns: true if this is an Attro link that should be handled
    public static func isAttroLink(_ url: URL) -> Bool {
        let allowedHosts = currentState().config?.allowedHosts ?? []
        return URLParser.isAttroLink(url, allowedHosts: allowedHosts)
    }

    // MARK: - Attribution Storage

    /// Store attribution data locally, awaiting completion.
    ///
    /// Prefer this variant when you intend to read the attribution back (e.g.
    /// `applyStoredAttributionToRevenueCat()` / `getStoredAttribution()`) right
    /// after storing it: awaiting guarantees the write has landed, so a
    /// store-then-read sequence cannot observe a stale/nil value.
    ///
    /// - Parameter attribution: The attribution data to store
    /// - Throws: `AttroError` if the attribution could not be persisted.
    public static func storeAttribution(_ attribution: Attribution) async throws {
        do {
            try await storage.setStoredAttribution(attribution)
        } catch {
            throw AttroError.persistenceFailed(error)
        }
    }

    /// Store attribution data locally (fire-and-forget).
    ///
    /// Use this to persist attribution from Universal Links for later use when
    /// you do not need to read it back immediately. The write happens on a
    /// detached task; unlike the previous implementation a failure is **not**
    /// silently discarded — it is logged via the unified logging system
    /// (`subsystem == "com.attro.sdk"`). If you need to read the attribution back
    /// right after storing, use the `async throws` overload and `await` it
    /// instead so you observe the write completing.
    ///
    /// - Parameter attribution: The attribution data to store
    public static func storeAttribution(_ attribution: Attribution) {
        Task {
            do {
                try await storage.setStoredAttribution(attribution)
            } catch {
                AttroLog.error("Failed to store attribution: \(error.localizedDescription)")
            }
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
        let state = currentState()
        guard let client = state.client, let config = state.config else {
            throw AttroError.notConfigured
        }

        let request = MyAffiliateRequest(
            rideUserId: userId,
            orgSlug: orgSlug ?? config.organizationSlug
        )

        return try await client.post("/api/ios/my-affiliate", body: request)
    }

    // MARK: - P2P Referral Program

    /// Get the current user's peer-to-peer referral info (the in-app "invite a
    /// friend" screen) from `/api/ios/referral/me`.
    ///
    /// Lazily provisions the caller's invisible internal affiliate + a referral
    /// link on the program's offer, and returns the shareable code + live stats
    /// (rendered as a QR on-device from `shareUrl`). The referrer earns a token
    /// once a referred user reaches their first paid invoice.
    ///
    /// Two auth gates are required by the backend:
    ///  - the configured ``Configuration/apiKey`` (`x-api-key`), proving the
    ///    caller is the integrating app, and
    ///  - `accessToken`, the user's upstream (Ride Supabase) access token, sent
    ///    as a bearer. The affiliate identity is derived from the VERIFIED token
    ///    subject — pass a FRESH, non-expired token (e.g. Ride's
    ///    `ensureValidAccessToken()`).
    ///
    /// - Parameters:
    ///   - accessToken: The user's upstream access token (bearer).
    ///   - orgSlug: Organization slug (defaults to the configured one).
    ///   - projectSlug: Optional project slug (defaults server-side).
    ///   - provider: Identity-provider slug that issued `accessToken` (default "ride").
    /// - Returns: The user's referral code, share URL, and P2P stats.
    /// - Throws: `AttroError.notConfigured` if the SDK or its `apiKey` is unset,
    ///   `.missingParameter` for an empty token, or a network/server error.
    public static func getReferralProgram(
        accessToken: String,
        orgSlug: String? = nil,
        projectSlug: String? = nil,
        provider: String = "ride"
    ) async throws -> ReferralProgramInfo {
        let state = currentState()
        guard let client = state.client, let config = state.config else {
            throw AttroError.notConfigured
        }
        guard let apiKey = config.apiKey, !apiKey.isEmpty else {
            // The referral endpoints are gated by the server-to-server key; without
            // it the request can only ever 401, so fail fast with a clear cause.
            throw AttroError.missingParameter("apiKey")
        }
        let token = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw AttroError.missingParameter("accessToken")
        }

        let request = ReferralProgramRequest(
            orgSlug: orgSlug ?? config.organizationSlug,
            projectSlug: projectSlug,
            provider: provider
        )

        return try await client.post(
            "/api/ios/referral/me",
            body: request,
            apiKey: apiKey,
            bearerToken: token
        )
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
