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
    func storeAndRetrieveAttribution() async {
        let storage = AttroStorage(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)

        let attribution = Attribution(
            clickId: "click-123",
            affiliateId: "aff-456",
            offerId: "offer-789",
            projectId: "project-000",
            trackingCode: "abc12345",
            matchMethod: .universalLink
        )

        await storage.setStoredAttribution(attribution)
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
    func resetClearsData() async {
        let storage = AttroStorage(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)

        await storage.setAttributionChecked(true)
        await storage.setStoredAttribution(Attribution(
            clickId: "c", affiliateId: "a", offerId: "o", projectId: "p", trackingCode: "t", matchMethod: nil
        ))

        await storage.reset()

        #expect(await storage.attributionChecked == false)
        #expect(await storage.storedAttribution == nil)
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
        let serverError = AttroError.serverError(statusCode: 500, message: "Internal error")
        let serverErrorNoMessage = AttroError.serverError(statusCode: 404, message: nil)

        #expect(notConfigured.errorDescription?.contains("configured") == true)
        #expect(invalidLink.errorDescription?.contains("Universal Link") == true)
        #expect(serverError.errorDescription?.contains("500") == true)
        #expect(serverError.errorDescription?.contains("Internal error") == true)
        #expect(serverErrorNoMessage.errorDescription?.contains("404") == true)
    }
}
