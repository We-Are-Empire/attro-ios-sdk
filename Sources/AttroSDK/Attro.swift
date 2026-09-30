import Foundation

/// Attro SDK for iOS affiliate attribution (contract: Attro
/// `docs/contracts/ios-attribution.md`).
///
/// Attribution is **deterministic first**: the app reports a signal (a
/// Universal Link it was opened with, a code the user typed) and the server
/// checks it and stores an attribution row. The app only carries that row's id,
/// as the RevenueCat subscriber attribute `attro_attribution_id`. App Store
/// offer codes named after an affiliate's code need no app code at all.
/// IP + User-Agent matching is an opt-in fallback.
///
/// ```swift
/// // 1. At launch, after Purchases.configure(...)
/// Attro.configure(Attro.Configuration(appKey: "<app key>", publicSlug: "your-program"))
///
/// // 2. When the app is opened by a Universal Link (also when already installed)
/// let outcome = try await Attro.handleUniversalLink(url, appUserId: Purchases.shared.appUserID)
///
/// // 3. When the user types an affiliate code
/// let outcome = try await Attro.submitCode(code, appUserId: Purchases.shared.appUserID)
///
/// // 4. Before showing the paywall, point RevenueCat at the attribution
/// if let current = await Attro.currentAttribution() {
///     Purchases.shared.attribution.setAttributes(current.subscriberAttributes)
/// }
/// ```
///
/// `import AttroRevenueCat` provides one-call wrappers that read the RevenueCat
/// app user id and set the attribute for you.
public enum Attro {

    /// This SDK's version.
    public static let sdkVersion = "2.0.0"

    /// The RevenueCat subscriber attribute key the SDK sets.
    public static let attributionAttributeKey = SubscriberAttributes.attributionIdKey

    // MARK: - Configuration

    private static let stateLock = NSLock()
    private nonisolated(unsafe) static var _engine: AttroEngine?

    private static func currentEngine() throws -> AttroEngine {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let engine = _engine else { throw AttroError.notConfigured }
        return engine
    }

    /// Configure the SDK. Call once at launch. Each call replaces the whole
    /// configuration (last write wins).
    public static func configure(_ configuration: Configuration) {
        let storage = AttroStorage()
        let engine = AttroEngine(
            configuration: configuration,
            client: APIClient(baseURL: configuration.baseURL),
            storage: storage,
            installIds: KeychainInstallIdStore(),
            webKitUserAgent: WKWebViewUserAgentProvider()
        )
        install(engine)
        Task { await storage.purgeLegacyKeys() }
    }

    /// Install an engine (tests inject one with a stub HTTP session).
    static func install(_ engine: AttroEngine?) {
        stateLock.lock()
        _engine = engine
        stateLock.unlock()
    }

    /// The current configuration, nil before `configure`.
    public static var configuration: Configuration? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _engine?.configuration
    }

    /// Whether the SDK has been configured.
    public static var isConfigured: Bool { configuration != nil }

    // MARK: - Universal Links

    /// Parse `url` as one of this app's Attro Universal Links, without any
    /// network call. Nil when it is not one (or the SDK is not configured).
    public static func parseUniversalLink(_ url: URL) -> AttroLink? {
        guard let configuration,
              let link = AttroLink(url: url, configuration: configuration),
              configuration.project(for: link) != nil else {
            return nil
        }
        return link
    }

    /// Whether `url` is one of this app's Attro Universal Links.
    public static func isAttroLink(_ url: URL) -> Bool {
        parseUniversalLink(url) != nil
    }

    /// Report that the app was opened by `url` (contract §3.1). Call it for
    /// every open by a link, including when the app is already installed.
    ///
    /// - Parameters:
    ///   - url: the full Universal Link the app received.
    ///   - appUserId: the RevenueCat app user id now
    ///     (`Purchases.shared.appUserID`). The attribution is bound to it for
    ///     good.
    /// - Returns: nil when `url` is not an Attro link of this app (no request
    ///   is made); otherwise the server's answer. An attributed answer becomes
    ///   ``currentAttribution()``.
    /// - Throws: ``AttroError``. When ``AttroError/isRetryable`` the attempt is
    ///   kept and ``retryPendingAttributions()`` resends it with the same ids.
    @discardableResult
    public static func handleUniversalLink(_ url: URL, appUserId: String) async throws -> AttributionOutcome? {
        try await currentEngine().handleUniversalLink(url, appUserId: appUserId)
    }

    // MARK: - Typed codes

    /// Report an affiliate code the user typed (contract §3.2). Matching is
    /// exact and case-insensitive on the server.
    ///
    /// - Parameters:
    ///   - code: the code as typed (surrounding whitespace is trimmed).
    ///   - appUserId: the RevenueCat app user id now.
    ///   - publicSlug: the project to resolve the code in, for an app that
    ///     serves several projects. Nil means the main project.
    /// - Throws: ``AttroError``; ``AttroError/rateLimited(retryAfter:)`` after
    ///   10 guesses a minute per install.
    public static func submitCode(
        _ code: String,
        appUserId: String,
        publicSlug: String? = nil
    ) async throws -> AttributionOutcome {
        try await currentEngine().submitCode(code, appUserId: appUserId, publicSlug: publicSlug)
    }

    // MARK: - Probabilistic match (opt-in)

    /// The opt-in probabilistic install match (contract §3.3). Returns nil
    /// without any request unless ``Configuration/probabilisticMatching`` is
    /// on. It is also skipped once the install has a deterministic attribution
    /// and after a definitive answer. A probabilistic result never replaces a
    /// deterministic ``currentAttribution()``.
    ///
    /// Call it at launch, after `Purchases.configure`. Sends only the install
    /// id, the app user id (and token) and the app's WebKit User-Agent.
    @discardableResult
    public static func matchInstall(appUserId: String) async throws -> AttributionOutcome? {
        try await currentEngine().matchInstall(appUserId: appUserId)
    }

    // MARK: - Retry

    /// Resend link and code attempts that failed transiently (offline, `503`,
    /// `429`), with their original ids, so the server replays them instead of
    /// counting twice. Call it at launch and when the app becomes active.
    @discardableResult
    public static func retryPendingAttributions() async -> [AttributionOutcome] {
        guard let engine = try? currentEngine() else { return [] }
        return await engine.retryPendingAttributions()
    }

    // MARK: - Current attribution

    /// The attribution RevenueCat should point at: the last attributed answer,
    /// where a probabilistic answer never replaces a deterministic one.
    public static func currentAttribution() async -> AttributionResult? {
        guard let engine = try? currentEngine() else { return nil }
        return await engine.currentAttribution()
    }

    // MARK: - Refer-a-friend

    /// The signed-in user's affiliate link and stats from
    /// `POST /api/ios/my-affiliate`. `stats.earnings` is an exact ``Money``.
    ///
    /// - Parameters:
    ///   - accessToken: a fresh access token of the user from your identity
    ///     provider (sent as `Authorization: Bearer`).
    ///   - provider: the identity-provider slug enrolled for the project.
    public static func getMyAffiliate(accessToken: String, provider: String) async throws -> AffiliateInfo {
        try await currentEngine().getMyAffiliate(accessToken: accessToken, provider: provider)
    }

    /// The signed-in user's referral-program code, share URL and stats from
    /// `POST /api/ios/referral/me`.
    ///
    /// - Parameters:
    ///   - accessToken: a fresh access token of the user from your identity
    ///     provider (sent as `Authorization: Bearer`).
    ///   - provider: the identity-provider slug enrolled for the project.
    public static func getReferralProgram(accessToken: String, provider: String) async throws -> ReferralProgramInfo {
        try await currentEngine().getReferralProgram(accessToken: accessToken, provider: provider)
    }

    // MARK: - Testing / Debug

    /// Clear the SDK's stored state (current attribution, pending attempts,
    /// match status). The Keychain install id is kept: it lives as long as
    /// the install.
    public static func reset() async {
        await AttroStorage().reset()
    }
}
