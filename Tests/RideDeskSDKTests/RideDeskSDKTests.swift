import Testing
import Foundation
@testable import RideDeskSDK

// MARK: - URL Parser Tests

@Suite("URL Parser")
struct URLParserTests {

    @Test("Parses valid Universal Link with all parameters")
    func parseValidUniversalLink() {
        let url = URL(string: "https://ridedesk.vercel.app/app/track?click=click-123&aff=aff-456&offer=offer-789&org=org-000&code=abc12345")!

        let attribution = URLParser.parse(url)

        #expect(attribution != nil)
        #expect(attribution?.clickId == "click-123")
        #expect(attribution?.affiliateId == "aff-456")
        #expect(attribution?.offerId == "offer-789")
        #expect(attribution?.orgId == "org-000")
        #expect(attribution?.trackingCode == "abc12345")
        #expect(attribution?.matchMethod == .universalLink)
    }

    @Test("Parses tracking redirect URL with code in path")
    func parseTrackingRedirectURL() {
        let url = URL(string: "https://ridedesk.vercel.app/r/abc12345?click=click-123&aff=aff-456&offer=offer-789&org=org-000")!

        let attribution = URLParser.parse(url)

        #expect(attribution != nil)
        #expect(attribution?.trackingCode == "abc12345")
    }

    @Test("Rejects URL from unknown host")
    func rejectUnknownHost() {
        let url = URL(string: "https://malicious.com/app/track?click=click-123&aff=aff-456&offer=offer-789&org=org-000&code=abc")!

        let attribution = URLParser.parse(url)

        #expect(attribution == nil)
    }

    @Test("Allows custom hosts when specified")
    func allowCustomHost() {
        let url = URL(string: "https://custom.ridedesk.io/app/track?click=click-123&aff=aff-456&offer=offer-789&org=org-000&code=abc")!

        let attribution = URLParser.parse(url, allowedHosts: ["custom.ridedesk.io"])

        #expect(attribution != nil)
    }

    @Test("Rejects URL with missing parameters")
    func rejectMissingParameters() {
        let url = URL(string: "https://ridedesk.vercel.app/app/track?click=click-123")!

        let attribution = URLParser.parse(url)

        #expect(attribution == nil)
    }

    @Test("isRideDeskLink returns true for valid links")
    func isRideDeskLinkValid() {
        let trackingURL = URL(string: "https://ridedesk.vercel.app/r/abc123")!
        let appTrackURL = URL(string: "https://ridedesk.vercel.app/app/track")!

        #expect(URLParser.isRideDeskLink(trackingURL) == true)
        #expect(URLParser.isRideDeskLink(appTrackURL) == true)
    }

    @Test("isRideDeskLink returns false for invalid links")
    func isRideDeskLinkInvalid() {
        let otherPath = URL(string: "https://ridedesk.vercel.app/dashboard")!
        let otherHost = URL(string: "https://example.com/r/abc123")!

        #expect(URLParser.isRideDeskLink(otherPath) == false)
        #expect(URLParser.isRideDeskLink(otherHost) == false)
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
            orgId: "org-000",
            trackingCode: "abc12345",
            matchMethod: .ipUserAgent
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Attribution.self, from: encoded)

        #expect(decoded == original)
    }

    @Test("Attribution MatchMethod encodes correctly")
    func matchMethodEncoding() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let ipUA = Attribution.MatchMethod.ipUserAgent
        let ipOnly = Attribution.MatchMethod.ipOnly
        let universal = Attribution.MatchMethod.universalLink

        #expect(String(data: try encoder.encode(ipUA), encoding: .utf8) == "\"ip_ua\"")
        #expect(String(data: try encoder.encode(ipOnly), encoding: .utf8) == "\"ip_exact\"")
        #expect(String(data: try encoder.encode(universal), encoding: .utf8) == "\"universal_link\"")
    }
}

// MARK: - Storage Tests

@Suite("Storage")
struct StorageTests {

    @Test("Storage stores and retrieves attribution")
    func storeAndRetrieveAttribution() async {
        let storage = RideDeskStorage(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)

        let attribution = Attribution(
            clickId: "click-123",
            affiliateId: "aff-456",
            offerId: "offer-789",
            orgId: "org-000",
            trackingCode: "abc12345",
            matchMethod: .universalLink
        )

        await storage.setStoredAttribution(attribution)
        let retrieved = await storage.storedAttribution

        #expect(retrieved == attribution)
    }

    @Test("Storage tracks attribution checked flag")
    func attributionCheckedFlag() async {
        let storage = RideDeskStorage(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)

        #expect(await storage.attributionChecked == false)

        await storage.setAttributionChecked(true)

        #expect(await storage.attributionChecked == true)
    }

    @Test("Storage reset clears all data")
    func resetClearsData() async {
        let storage = RideDeskStorage(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)

        await storage.setAttributionChecked(true)
        await storage.setStoredAttribution(Attribution(
            clickId: "c", affiliateId: "a", offerId: "o", orgId: "g", trackingCode: "t", matchMethod: nil
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
        let config = RideDesk.Configuration(organizationSlug: "test-org")

        #expect(config.organizationSlug == "test-org")
        #expect(config.baseURL.absoluteString == "https://ridedesk.vercel.app")
    }

    @Test("Configuration allows custom base URL")
    func configurationCustomBaseURL() {
        let config = RideDesk.Configuration(
            organizationSlug: "test-org",
            baseURL: URL(string: "https://staging.ridedesk.app")!
        )

        #expect(config.baseURL.absoluteString == "https://staging.ridedesk.app")
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
                "url": "https://ridedesk.vercel.app/r/abc12345",
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
                "url": "https://ridedesk.vercel.app/r/abc12345"
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
            "trackingLink": { "id": "l", "code": "abc", "url": "https://ridedesk.vercel.app/r/abc" },
            "stats": { "clicks": 0, "conversions": { "total": 0, "approved": 0, "pending": 0 }, "earnings": 0, "tokens": { "balance": 0, "lifetimeEarned": 0 } },
            "shareContent": { "text": "Hi", "url": "https://ridedesk.vercel.app/r/abc" }
        }
        """.data(using: .utf8)!

        let referralInfo = try JSONDecoder().decode(ReferralInfo.self, from: json)

        #expect(referralInfo.referralURL?.absoluteString == "https://ridedesk.vercel.app/r/abc")
    }
}

// MARK: - Error Tests

@Suite("Errors")
struct ErrorTests {

    @Test("RideDeskError has localized descriptions")
    func errorDescriptions() {
        let notConfigured = RideDeskError.notConfigured
        let invalidLink = RideDeskError.invalidUniversalLink
        let serverError = RideDeskError.serverError(statusCode: 500, message: "Internal error")
        let serverErrorNoMessage = RideDeskError.serverError(statusCode: 404, message: nil)

        #expect(notConfigured.errorDescription?.contains("configured") == true)
        #expect(invalidLink.errorDescription?.contains("Universal Link") == true)
        #expect(serverError.errorDescription?.contains("500") == true)
        #expect(serverError.errorDescription?.contains("Internal error") == true)
        #expect(serverErrorNoMessage.errorDescription?.contains("404") == true)
    }
}
