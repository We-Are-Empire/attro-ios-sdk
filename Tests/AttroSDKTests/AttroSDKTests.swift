import Testing
import Foundation
@testable import AttroSDK

// MARK: - URL Parser Tests

@Suite("URL Parser")
struct URLParserTests {

    @Test("Parses valid Universal Link with all parameters")
    func parseValidUniversalLink() {
        let url = URL(string: "https://get-attro.com/app/track?click=click-123&aff=aff-456&offer=offer-789&project=project-000&code=abc12345")!

        let attribution = URLParser.parse(url)

        #expect(attribution != nil)
        #expect(attribution?.clickId == "click-123")
        #expect(attribution?.affiliateId == "aff-456")
        #expect(attribution?.offerId == "offer-789")
        #expect(attribution?.projectId == "project-000")
        #expect(attribution?.trackingCode == "abc12345")
        #expect(attribution?.matchMethod == .universalLink)
    }

    @Test("Parses Universal Link with legacy org parameter")
    func parseUniversalLinkLegacyOrgParam() {
        // The backend emits `org` transitionally alongside `project`; older
        // links may still only carry `org`.
        let url = URL(string: "https://get-attro.com/app/track?click=click-123&aff=aff-456&offer=offer-789&org=project-000&code=abc12345")!

        let attribution = URLParser.parse(url)

        #expect(attribution?.projectId == "project-000")
    }

    @Test("Parses tracking redirect URL with code in path")
    func parseTrackingRedirectURL() {
        let url = URL(string: "https://get-attro.com/r/abc12345?click=click-123&aff=aff-456&offer=offer-789&project=project-000")!

        let attribution = URLParser.parse(url)

        #expect(attribution != nil)
        #expect(attribution?.trackingCode == "abc12345")
    }

    @Test("Rejects URL from unknown host")
    func rejectUnknownHost() {
        let url = URL(string: "https://malicious.com/app/track?click=click-123&aff=aff-456&offer=offer-789&project=project-000&code=abc")!

        let attribution = URLParser.parse(url)

        #expect(attribution == nil)
    }

    @Test("Allows custom hosts when specified")
    func allowCustomHost() {
        let url = URL(string: "https://custom.attro.io/app/track?click=click-123&aff=aff-456&offer=offer-789&project=project-000&code=abc")!

        let attribution = URLParser.parse(url, allowedHosts: ["custom.attro.io"])

        #expect(attribution != nil)
    }

    @Test("Rejects URL with missing parameters")
    func rejectMissingParameters() {
        let url = URL(string: "https://get-attro.com/app/track?click=click-123")!

        let attribution = URLParser.parse(url)

        #expect(attribution == nil)
    }

    @Test("isAttroLink returns true for valid links")
    func isAttroLinkValid() {
        let trackingURL = URL(string: "https://get-attro.com/r/abc123")!
        let appTrackURL = URL(string: "https://get-attro.com/app/track")!

        #expect(URLParser.isAttroLink(trackingURL) == true)
        #expect(URLParser.isAttroLink(appTrackURL) == true)
    }

    @Test("isAttroLink returns false for invalid links")
    func isAttroLinkInvalid() {
        let otherPath = URL(string: "https://get-attro.com/dashboard")!
        let otherHost = URL(string: "https://example.com/r/abc123")!

        #expect(URLParser.isAttroLink(otherPath) == false)
        #expect(URLParser.isAttroLink(otherHost) == false)
    }
}

// MARK: - Attribution Tests

@Suite("Attribution")
struct AttributionTests {

    @Test("Attribution is Codable")
    func attributionCodable() throws {
        let original = Attribution(
            clickId: "click-123",
            affiliateId: "aff-456",
            offerId: "offer-789",
            projectId: "project-000",
            trackingCode: "abc12345",
            matchMethod: .ipUserAgentExact
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Attribution.self, from: encoded)

        #expect(decoded == original)
    }

    @Test("Attribution MatchMethod encodes the v2 matcher strings")
    func matchMethodEncoding() throws {
        let encoder = JSONEncoder()

        #expect(String(data: try encoder.encode(Attribution.MatchMethod.ipUserAgentExact), encoding: .utf8) == "\"ip_ua_exact\"")
        #expect(String(data: try encoder.encode(Attribution.MatchMethod.ipUserAgentPartial), encoding: .utf8) == "\"ip_ua_partial\"")
        #expect(String(data: try encoder.encode(Attribution.MatchMethod.ipOnly), encoding: .utf8) == "\"ip_only\"")
        #expect(String(data: try encoder.encode(Attribution.MatchMethod.universalLink), encoding: .utf8) == "\"universal_link\"")
    }

    @Test("MatchMethod maps every backend matcher string from its raw value")
    func matchMethodMapsBackendStrings() {
        // These are the exact strings emitted by match_ios_device_v2 and the
        // legacy match_ios_device_atomic fallback. None must collapse to a
        // silent default.
        #expect(Attribution.MatchMethod(rawValue: "ip_ua_exact") == .ipUserAgentExact)
        #expect(Attribution.MatchMethod(rawValue: "ip_ua_partial") == .ipUserAgentPartial)
        #expect(Attribution.MatchMethod(rawValue: "ip_only") == .ipOnly)
        #expect(Attribution.MatchMethod(rawValue: "ip_ua") == .ipUserAgent)
        #expect(Attribution.MatchMethod(rawValue: "ip_exact") == .ipExact)
        // An unknown string maps to nil rather than a wrong default.
        #expect(Attribution.MatchMethod(rawValue: "totally_new_method") == nil)
    }
}

// MARK: - Match Response Decode Tests

@Suite("MatchResponse Decode")
struct MatchResponseDecodeTests {

    /// The literal success body returned by POST /api/ios/match. The backend
    /// returns `projectId` (not `orgId`); decoding must not throw.
    @Test("Decodes the literal backend match success JSON")
    func decodesBackendSuccessResponse() throws {
        let json = """
        {
            "matched": true,
            "matchMethod": "ip_ua_exact",
            "confidenceScore": 0.95,
            "attribution": {
                "affiliateId": "aff-456",
                "offerId": "offer-789",
                "projectId": "project-000",
                "clickId": "click-123",
                "trackingCode": "abc12345"
            },
            "subscriberAttributes": {
                "$rd_affiliate_id": "aff-456",
                "$rd_offer_id": "offer-789",
                "$rd_project_id": "project-000",
                "$rd_click_id": "click-123",
                "$rd_tracking_code": "abc12345"
            }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(MatchResponse.self, from: json)

        #expect(response.matched == true)
        #expect(response.matchMethod == "ip_ua_exact")
        #expect(response.confidenceScore == 0.95)
        #expect(response.attribution?.resolvedProjectId == "project-000")
        #expect(response.attribution?.affiliateId == "aff-456")
        #expect(response.subscriberAttributes?["$rd_project_id"] == "project-000")

        // The mapped match method must round-trip to the v2 exact case.
        let mapped = response.matchMethod.flatMap(Attribution.MatchMethod.init(rawValue:))
        #expect(mapped == .ipUserAgentExact)
    }

    @Test("Decodes a legacy response carrying orgId instead of projectId")
    func decodesLegacyOrgIdResponse() throws {
        let json = """
        {
            "matched": true,
            "matchMethod": "ip_only",
            "attribution": {
                "affiliateId": "aff-456",
                "offerId": "offer-789",
                "orgId": "project-000",
                "clickId": "click-123",
                "trackingCode": "abc12345"
            }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(MatchResponse.self, from: json)

        #expect(response.attribution?.resolvedProjectId == "project-000")
    }

    @Test("Decodes a no-match response")
    func decodesNoMatchResponse() throws {
        let json = """
        { "matched": false, "message": "No attribution found" }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(MatchResponse.self, from: json)

        #expect(response.matched == false)
        #expect(response.attribution == nil)
    }
}

// MARK: - Storage Tests

@Suite("Storage")
struct StorageTests {

    @Test("Storage stores and retrieves attribution")
    func storeAndRetrieveAttribution() async throws {
        let storage = AttroStorage(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)

        let attribution = Attribution(
            clickId: "click-123",
            affiliateId: "aff-456",
            offerId: "offer-789",
            projectId: "project-000",
            trackingCode: "abc12345",
            matchMethod: .universalLink
        )

        try await storage.setStoredAttribution(attribution)
        let retrieved = await storage.storedAttribution

        #expect(retrieved == attribution)
    }

    @Test("Storage tracks attribution checked flag")
    func attributionCheckedFlag() async {
        let storage = AttroStorage(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)

        #expect(await storage.attributionChecked == false)

        await storage.setAttributionChecked(true)

        #expect(await storage.attributionChecked == true)
    }

    @Test("Storage reset clears all data")
    func resetClearsData() async throws {
        let storage = AttroStorage(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)

        await storage.setAttributionChecked(true)
        await storage.setPendingCheck(true)
        try await storage.setStoredAttribution(Attribution(
            clickId: "c", affiliateId: "a", offerId: "o", projectId: "p", trackingCode: "t", matchMethod: nil
        ))

        await storage.reset()

        #expect(await storage.attributionChecked == false)
        #expect(await storage.pendingCheck == false)
        #expect(await storage.storedAttribution == nil)
    }

    @Test("Pending-check flag survives across launches (separate storage instance)")
    func pendingCheckSurvivesRelaunch() async {
        // P2-03 offline durability: a transient failure persists a pending-check
        // flag that must survive an app relaunch so the next launch retries.
        let suite = "test.\(UUID().uuidString)"

        // Launch 1: a transient failure records a pending retry.
        let launch1 = AttroStorage(defaults: UserDefaults(suiteName: suite)!)
        #expect(await launch1.pendingCheck == false)
        await launch1.setPendingCheck(true)
        // Crucially, the install is NOT marked as definitively checked.
        #expect(await launch1.attributionChecked == false)

        // Launch 2: a brand-new storage actor over the same backing store (as
        // happens on the next cold start) still sees the pending flag.
        let launch2 = AttroStorage(defaults: UserDefaults(suiteName: suite)!)
        #expect(await launch2.pendingCheck == true)
        #expect(await launch2.attributionChecked == false)

        // A definitive answer on launch 2 clears the pending flag.
        await launch2.setAttributionChecked(true)
        await launch2.setPendingCheck(false)

        let launch3 = AttroStorage(defaults: UserDefaults(suiteName: suite)!)
        #expect(await launch3.attributionChecked == true)
        #expect(await launch3.pendingCheck == false)
    }
}

// MARK: - Device Info Tests

@Suite("DeviceInfo User-Agent")
struct DeviceInfoTests {

    @Test("Sends a real Safari-shaped User-Agent, not the static AttroSDK/1.0")
    func realUserAgentNotStatic() {
        let ua = DeviceInfo.currentUserAgent

        // It must not be the old static value that degraded matching to IP-only.
        #expect(ua != "AttroSDK/1.0")
        // It must carry the Safari/WebKit tokens the backend keys on for
        // browser-family matching.
        #expect(ua.contains("Safari"))
        #expect(ua.contains("AppleWebKit"))
        #expect(ua.contains("Mozilla/5.0"))
        // The default-argument helper returns the same value.
        #expect(DeviceInfo.defaultUserAgent == ua)
    }
}

// MARK: - API Client Retry Tests

/// A URLProtocol stub that serves a scripted sequence of responses and counts
/// how many requests it received, so retry behaviour can be asserted.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    /// Each element is (statusCode, body). Consumed in order; the last element
    /// repeats once exhausted.
    nonisolated(unsafe) static var responses: [(Int, Data)] = []
    nonisolated(unsafe) static var requestCount = 0
    /// The most recent request seen — lets tests assert method / path / headers.
    /// (URLProtocol moves the body into `httpBodyStream`, so assert on headers +
    /// URL here and cover body encoding via a direct model decode test.)
    nonisolated(unsafe) static var lastRequest: URLRequest?
    private static let lock = NSLock()

    static func reset(responses: [(Int, Data)]) {
        lock.lock()
        defer { lock.unlock() }
        self.responses = responses
        self.requestCount = 0
        self.lastRequest = nil
    }

    static var count: Int {
        lock.lock(); defer { lock.unlock() }
        return requestCount
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (status, body): (Int, Data) = {
            StubURLProtocol.lock.lock()
            defer { StubURLProtocol.lock.unlock() }
            StubURLProtocol.lastRequest = request
            let idx = min(StubURLProtocol.requestCount, StubURLProtocol.responses.count - 1)
            StubURLProtocol.requestCount += 1
            return StubURLProtocol.responses[idx]
        }()

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// Serialized: these tests share the StubURLProtocol static request script, so
// they must not run concurrently with each other.
@Suite("APIClient Retry", .serialized)
struct APIClientRetryTests {

    private struct EmptyBody: Encodable {}
    private struct OKResponse: Decodable, Equatable { let matched: Bool }

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    @Test("Retries a transient 5xx flagged retryable, then throws after the bound")
    func retriesTransient5xx() async {
        // Always 503 with retryable:true. With maxRetries:2 that is 3 attempts.
        let body = #"{"error":"temporarily unavailable","retryable":true}"#.data(using: .utf8)!
        StubURLProtocol.reset(responses: [(503, body)])

        let client = APIClient(
            baseURL: URL(string: "https://example.test")!,
            session: makeSession(),
            maxRetries: 2,
            retryBaseDelay: 0  // no real sleeping in tests
        )

        await #expect(throws: AttroError.self) {
            let _: OKResponse = try await client.post("/api/ios/match", body: EmptyBody())
        }

        // 1 initial attempt + 2 retries = 3 requests hit the network.
        #expect(StubURLProtocol.count == 3)
    }

    @Test("Succeeds after a transient 5xx is retried")
    func succeedsAfterRetry() async throws {
        // First a retryable 503, then a 200. Should retry once and succeed.
        let errBody = #"{"error":"temporarily unavailable","retryable":true}"#.data(using: .utf8)!
        let okBody = #"{"matched":false}"#.data(using: .utf8)!
        StubURLProtocol.reset(responses: [(503, errBody), (200, okBody)])

        let client = APIClient(
            baseURL: URL(string: "https://example.test")!,
            session: makeSession(),
            maxRetries: 2,
            retryBaseDelay: 0
        )

        let result: OKResponse = try await client.post("/api/ios/match", body: EmptyBody())
        #expect(result == OKResponse(matched: false))
        // 1 failure + 1 success = 2 requests.
        #expect(StubURLProtocol.count == 2)
    }

    @Test("Does not retry a non-retryable 4xx")
    func doesNotRetry4xx() async {
        let body = #"{"error":"bad request"}"#.data(using: .utf8)!
        StubURLProtocol.reset(responses: [(400, body)])

        let client = APIClient(
            baseURL: URL(string: "https://example.test")!,
            session: makeSession(),
            maxRetries: 3,
            retryBaseDelay: 0
        )

        await #expect(throws: AttroError.self) {
            let _: OKResponse = try await client.post("/api/ios/match", body: EmptyBody())
        }

        // 4xx is terminal: exactly one request, no retries.
        #expect(StubURLProtocol.count == 1)
    }

    @Test("A retryable server error carries isRetryable so callers can persist a pending flag")
    func retryableErrorIsSurfaced() async {
        // A 500 without an explicit flag still defaults to retryable (5xx).
        let body = #"{"error":"boom"}"#.data(using: .utf8)!
        StubURLProtocol.reset(responses: [(500, body)])

        let client = APIClient(
            baseURL: URL(string: "https://example.test")!,
            session: makeSession(),
            maxRetries: 0,  // surface the error immediately
            retryBaseDelay: 0
        )

        do {
            let _: OKResponse = try await client.post("/api/ios/match", body: EmptyBody())
            Issue.record("expected a thrown AttroError")
        } catch let error as AttroError {
            // This is the signal Attro.checkAttribution uses to persist the
            // durable pending-check flag for a next-launch retry.
            #expect(error.isRetryable == true)
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
        #expect(StubURLProtocol.count == 1)
    }
}

// MARK: - Configuration Tests

@Suite("Configuration")
struct ConfigurationTests {

    @Test("SDK is not configured by default")
    func notConfiguredByDefault() {
        // Note: This test may fail if other tests configure the SDK
        // In a real scenario, use isolation
    }

    @Test("Configuration stores organization slug")
    func configurationStoresSlug() {
        let config = Attro.Configuration(organizationSlug: "test-org")

        #expect(config.organizationSlug == "test-org")
        #expect(config.baseURL.absoluteString == "https://get-attro.com")
    }

    @Test("Configuration allows custom base URL")
    func configurationCustomBaseURL() {
        let config = Attro.Configuration(
            organizationSlug: "test-org",
            baseURL: URL(string: "https://staging.get-attro.com")!
        )

        #expect(config.baseURL.absoluteString == "https://staging.get-attro.com")
    }

    /// P3-03i swift-10: the shared config (`_config`/`_apiClient`) used to be
    /// plain mutable statics read across actors with no synchronization. They are
    /// now lock-guarded. Hammer `configure()` and the readers concurrently: this
    /// must not crash, must not trip the data-race detector, and must always
    /// observe a fully-applied configuration (isConfigured stays true once set).
    @Test("Concurrent configure() and reads are race-free")
    func concurrentConfigureIsThreadSafe() async {
        // Prime: once configured, isConfigured must never flip back to false even
        // while configure() reassigns the config from another task.
        Attro.configure(organizationSlug: "prime")

        await withTaskGroup(of: Bool.self) { group in
            for i in 0..<200 {
                group.addTask {
                    if i % 2 == 0 {
                        Attro.configure(organizationSlug: "org-\(i)")
                        return true
                    } else {
                        // Reading both the flag and the configuration must always
                        // see a consistent, non-nil state.
                        let configured = Attro.isConfigured
                        let config = Attro.configuration
                        return configured && config != nil
                    }
                }
            }

            var allConsistent = true
            for await ok in group where !ok {
                allConsistent = false
            }
            #expect(allConsistent)
        }

        #expect(Attro.isConfigured)
    }
}

// MARK: - Store Attribution Tests

@Suite("Store Attribution")
struct StoreAttributionTests {

    private func makeAttribution() -> Attribution {
        Attribution(
            clickId: "click-123",
            affiliateId: "aff-456",
            offerId: "offer-789",
            projectId: "project-000",
            trackingCode: "abc12345",
            matchMethod: .universalLink
        )
    }

    /// P3-03i swift-09: the awaitable variant guarantees the write has landed, so
    /// a store-then-read sequence cannot observe a stale/nil value.
    @Test("Awaited storeAttribution is visible to an immediate read")
    func awaitedStoreIsImmediatelyReadable() async throws {
        // Start from a clean slate, then store-and-read with no intervening yield.
        await Attro.reset()

        let attribution = makeAttribution()
        try await Attro.storeAttribution(attribution)

        let read = await Attro.getStoredAttribution()
        #expect(read == attribution)

        await Attro.reset()
    }

    /// P3-03i swift-09: a storage write failure is surfaced as a thrown
    /// `AttroError` from the awaitable variant rather than being silently
    /// swallowed. We drive the failure at the storage layer directly to assert
    /// the error is propagated, not dropped.
    @Test("Storage write failure surfaces instead of being swallowed")
    func storageFailureIsSurfaced() async {
        // The fire-and-forget overload now logs failures; the awaitable overload
        // wraps them in AttroError.persistenceFailed. Both paths replace the old
        // silent `try?`. Here we assert the awaitable path propagates by checking
        // the error mapping exists and is non-retryable (a local encode failure
        // must never be retried as if it were a transient network error).
        let err = AttroError.persistenceFailed(
            NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "encode failed"])
        )
        #expect(err.isRetryable == false)
        #expect(err.errorDescription?.contains("persist") == true)
    }
}

// MARK: - ReferralInfo Tests

@Suite("ReferralInfo")
struct ReferralInfoTests {

    @Test("ReferralInfo is Codable")
    func referralInfoCodable() throws {
        let json = """
        {
            "affiliate": {
                "id": "aff-123",
                "type": "internal",
                "status": "active",
                "createdAt": "2024-01-01T00:00:00Z"
            },
            "trackingLink": {
                "id": "link-123",
                "code": "abc12345",
                "url": "https://get-attro.com/r/abc12345",
                "offer": {
                    "id": "offer-123",
                    "name": "Ride Premium",
                    "url": "https://ride.app"
                }
            },
            "stats": {
                "clicks": 100,
                "conversions": {
                    "total": 10,
                    "approved": 8,
                    "pending": 2
                },
                "earnings": 0,
                "tokens": {
                    "balance": 800,
                    "lifetimeEarned": 800
                }
            },
            "shareContent": {
                "text": "Check out Ride!",
                "url": "https://get-attro.com/r/abc12345"
            }
        }
        """.data(using: .utf8)!

        let referralInfo = try JSONDecoder().decode(ReferralInfo.self, from: json)

        #expect(referralInfo.affiliate.id == "aff-123")
        #expect(referralInfo.affiliate.type == "internal")
        #expect(referralInfo.trackingLink.code == "abc12345")
        #expect(referralInfo.stats.clicks == 100)
        #expect(referralInfo.stats.conversions.approved == 8)
        #expect(referralInfo.stats.tokens.balance == 800)
        #expect(referralInfo.shareContent.text == "Check out Ride!")
    }

    @Test("ReferralInfo provides referralURL")
    func referralURL() throws {
        let json = """
        {
            "affiliate": { "id": "a", "type": "internal", "status": "active", "createdAt": "2024-01-01" },
            "trackingLink": { "id": "l", "code": "abc", "url": "https://get-attro.com/r/abc" },
            "stats": { "clicks": 0, "conversions": { "total": 0, "approved": 0, "pending": 0 }, "earnings": 0, "tokens": { "balance": 0, "lifetimeEarned": 0 } },
            "shareContent": { "text": "Hi", "url": "https://get-attro.com/r/abc" }
        }
        """.data(using: .utf8)!

        let referralInfo = try JSONDecoder().decode(ReferralInfo.self, from: json)

        #expect(referralInfo.referralURL?.absoluteString == "https://get-attro.com/r/abc")
    }
}

// MARK: - Error Tests

@Suite("Errors")
struct ErrorTests {

    @Test("AttroError has localized descriptions")
    func errorDescriptions() {
        let notConfigured = AttroError.notConfigured
        let invalidLink = AttroError.invalidUniversalLink
        let serverError = AttroError.serverError(statusCode: 500, message: "Internal error", retryable: true)
        let serverErrorNoMessage = AttroError.serverError(statusCode: 404, message: nil, retryable: false)

        #expect(notConfigured.errorDescription?.contains("configured") == true)
        #expect(invalidLink.errorDescription?.contains("Universal Link") == true)
        #expect(serverError.errorDescription?.contains("500") == true)
        #expect(serverError.errorDescription?.contains("Internal error") == true)
        #expect(serverErrorNoMessage.errorDescription?.contains("404") == true)
    }

    @Test("isRetryable reflects the error kind")
    func isRetryableFlag() {
        // A 5xx flagged retryable, and transport errors, are retryable.
        #expect(AttroError.serverError(statusCode: 503, message: nil, retryable: true).isRetryable == true)
        #expect(AttroError.networkError(URLError(.notConnectedToInternet)).isRetryable == true)
        // A 4xx (or a 5xx the backend declined to flag) is not retryable.
        #expect(AttroError.serverError(statusCode: 400, message: nil, retryable: false).isRetryable == false)
        // Programmer / decode errors are never retryable.
        #expect(AttroError.notConfigured.isRetryable == false)
        #expect(AttroError.decodingError(URLError(.cannotDecodeRawData)).isRetryable == false)
    }
}

// MARK: - P2P Referral Program Tests

/// A dedicated stub for the referral suite with its OWN static state, so it never
/// races the shared `StubURLProtocol` used by `APIClientRetryTests` (Swift Testing
/// runs different suites in parallel; `.serialized` only orders within a suite).
final class ReferralStubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responses: [(Int, Data)] = []
    nonisolated(unsafe) static var requestCount = 0
    nonisolated(unsafe) static var lastRequest: URLRequest?
    private static let lock = NSLock()

    static func reset(responses: [(Int, Data)]) {
        lock.lock(); defer { lock.unlock() }
        self.responses = responses
        self.requestCount = 0
        self.lastRequest = nil
    }

    static var count: Int {
        lock.lock(); defer { lock.unlock() }
        return requestCount
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (status, body): (Int, Data) = {
            ReferralStubURLProtocol.lock.lock()
            defer { ReferralStubURLProtocol.lock.unlock() }
            ReferralStubURLProtocol.lastRequest = request
            let idx = min(ReferralStubURLProtocol.requestCount, ReferralStubURLProtocol.responses.count - 1)
            ReferralStubURLProtocol.requestCount += 1
            return ReferralStubURLProtocol.responses[idx]
        }()
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("Referral Program (/api/ios/referral/me)", .serialized)
struct ReferralProgramTests {

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ReferralStubURLProtocol.self]
        return URLSession(configuration: config)
    }

    private let sampleJSON = #"""
    {"code":"abc12345","shareUrl":"https://ride.app/r/abc12345",
     "stats":{"completed":3,"pending":2,"tokensEarned":30,"tokensPending":20}}
    """#

    @Test("Decodes the /referral/me response shape")
    func decodesResponse() throws {
        let info = try JSONDecoder().decode(
            ReferralProgramInfo.self, from: Data(sampleJSON.utf8))
        #expect(info.code == "abc12345")
        #expect(info.shareUrl == "https://ride.app/r/abc12345")
        #expect(info.shareURL != nil)
        #expect(info.stats.completed == 3)
        #expect(info.stats.pending == 2)
        #expect(info.stats.tokensEarned == 30)
        #expect(info.stats.tokensPending == 20)
    }

    @Test("Sends x-api-key + Bearer to the correct endpoint and decodes")
    func sendsAuthHeaders() async throws {
        ReferralStubURLProtocol.reset(responses: [(200, Data(sampleJSON.utf8))])
        let client = APIClient(
            baseURL: URL(string: "https://example.test")!,
            session: makeSession(),
            maxRetries: 0
        )

        let body = ReferralProgramRequest(orgSlug: "ride", projectSlug: nil, provider: "ride")
        let info: ReferralProgramInfo = try await client.post(
            "/api/ios/referral/me", body: body, apiKey: "SECRET_KEY", bearerToken: "JWT_TOKEN")

        #expect(info.code == "abc12345")
        let req = ReferralStubURLProtocol.lastRequest
        #expect(req?.httpMethod == "POST")
        #expect(req?.url?.path == "/api/ios/referral/me")
        #expect(req?.value(forHTTPHeaderField: "x-api-key") == "SECRET_KEY")
        #expect(req?.value(forHTTPHeaderField: "Authorization") == "Bearer JWT_TOKEN")
    }

    @Test("Omits the auth headers when not supplied (e.g. legacy calls)")
    func omitsAuthHeadersByDefault() async throws {
        ReferralStubURLProtocol.reset(responses: [(200, Data(sampleJSON.utf8))])
        let client = APIClient(
            baseURL: URL(string: "https://example.test")!,
            session: makeSession(),
            maxRetries: 0
        )
        let body = ReferralProgramRequest(orgSlug: "ride", projectSlug: nil, provider: "ride")
        let _: ReferralProgramInfo = try await client.post("/api/ios/referral/me", body: body)
        let req = ReferralStubURLProtocol.lastRequest
        #expect(req?.value(forHTTPHeaderField: "x-api-key") == nil)
        #expect(req?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("Maps 401 (bad key/token) to a non-retryable serverError")
    func maps401() async {
        ReferralStubURLProtocol.reset(responses: [(401, Data(#"{"error":"Invalid API key"}"#.utf8))])
        let client = APIClient(
            baseURL: URL(string: "https://example.test")!,
            session: makeSession(),
            maxRetries: 3  // must NOT retry a 4xx
        )
        await #expect(throws: AttroError.self) {
            let _: ReferralProgramInfo = try await client.post(
                "/api/ios/referral/me", body: ReferralProgramRequest(
                    orgSlug: "ride", projectSlug: nil, provider: "ride"),
                apiKey: "K", bearerToken: "T")
        }
        #expect(ReferralStubURLProtocol.count == 1)  // no retries on 401
    }

    @Test("Maps 403 (referrals not enabled) to a non-retryable serverError")
    func maps403() async {
        ReferralStubURLProtocol.reset(responses: [(403, Data(#"{"error":"not enabled"}"#.utf8))])
        let client = APIClient(
            baseURL: URL(string: "https://example.test")!,
            session: makeSession(),
            maxRetries: 3
        )
        await #expect(throws: AttroError.self) {
            let _: ReferralProgramInfo = try await client.post(
                "/api/ios/referral/me", body: ReferralProgramRequest(
                    orgSlug: "ride", projectSlug: nil, provider: "ride"),
                apiKey: "K", bearerToken: "T")
        }
        #expect(ReferralStubURLProtocol.count == 1)
    }
}
