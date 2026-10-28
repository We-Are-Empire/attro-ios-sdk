import Testing
import Foundation
@testable import AttroSDK

@Suite("Refer-a-friend endpoints")
struct ReferralTests {
    @Test("my-affiliate: POSTs { provider } with the app key and the bearer token, decodes Money")
    func myAffiliate() async throws {
        let h = Harness([.fixture(200, "my-affiliate-usd")])
        let info = try await h.engine.getMyAffiliate(accessToken: " upstream-token ", provider: "demo-idp")

        let request = try #require(h.server.requests.first)
        #expect(request.url.path == "/api/app/my-affiliate")
        #expect(request.header("x-api-key") == "app_key_main")
        #expect(request.header("Authorization") == "Bearer upstream-token")
        #expect(request.jsonKeys == ["provider"])
        #expect(request.json["provider"] as? String == "demo-idp")

        #expect(info.stats.earnings == (try Money(amount: "12.34", amountMinor: 1234, currency: "USD")))
        #expect(info.stats.earningsFormatted == "$12.34")
        #expect(info.stats.conversions.total == 3)
        #expect(info.trackingLink.url == "https://get-attro.com/a/demo-app/abc12345")
        #expect(info.trackingLink.offer?.name == "Premium")
        #expect(info.referralURL?.path == "/a/demo-app/abc12345")
    }

    @Test("my-affiliate: a link without an offer decodes")
    func nullOffer() throws {
        let info = try JSONDecoder().decode(AffiliateInfo.self, from: Fixture.data("my-affiliate-jpy"))
        #expect(info.trackingLink.offer == nil)
        #expect(info.stats.earnings.minorUnitExponent == 0)
    }

    @Test("referral/me: POSTs { provider } with both credentials and decodes the program")
    func referralMe() async throws {
        let h = Harness([.fixture(200, "referral-me")])
        let info = try await h.engine.getReferralProgram(accessToken: "tok", provider: "demo-idp")
        let request = try #require(h.server.requests.first)
        #expect(request.url.path == "/api/app/referral/me")
        #expect(request.header("x-api-key") == "app_key_main")
        #expect(request.header("Authorization") == "Bearer tok")
        #expect(request.jsonKeys == ["provider"])
        #expect(info.code == "abc12345")
        #expect(info.stats.tokenBalance == 1)
        #expect(info.defaultReward?.fulfillmentData?.discountPercent == 20)
        #expect(info.shareURL != nil)
    }

    @Test("referral/me: unknown fulfillment_data shapes do not fail the response")
    func freeFormFulfillment() throws {
        var object = Fixture.json("referral-me")
        var reward = object["defaultReward"] as! [String: Any]
        reward["fulfillmentData"] = ["discount_percent": "twenty", "extra": [1, 2]]
        object["defaultReward"] = reward
        let info = try JSONDecoder().decode(ReferralProgramInfo.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(info.defaultReward?.fulfillmentData?.discountPercent == nil)
        #expect(info.defaultReward?.tokenCost == 1)
    }

    @Test("Empty token or provider fail fast without a request")
    func validation() async {
        let h = Harness([.fixture(200, "referral-me")])
        await #expect(throws: AttroError.self) { try await h.engine.getReferralProgram(accessToken: " ", provider: "p") }
        await #expect(throws: AttroError.self) { try await h.engine.getMyAffiliate(accessToken: "t", provider: "") }
        #expect(h.server.requests.isEmpty)
    }

    @Test("401 is surfaced once, never retried")
    func unauthorized() async {
        let h = Harness([StubResponse(401, Data(#"{"error":"Invalid or missing access token"}"#.utf8))])
        await #expect(throws: AttroError.self) { try await h.engine.getMyAffiliate(accessToken: "t", provider: "p") }
        #expect(h.server.requests.count == 1)
    }
}

@Suite("HTTP client")
struct APIClientTests {
    @Test("A 5xx without a retryable flag falls back to retryable")
    func fiveHundred() async {
        let h = Harness([StubResponse(500, Data(#"{"error":"Internal server error"}"#.utf8))])
        await #expect(throws: AttroError.self) { try await h.engine.getMyAffiliate(accessToken: "t", provider: "p") }
        #expect(h.server.requests.count == 3)
    }

    @Test("A non-JSON error body is still classified")
    func nonJSONError() async {
        let h = Harness([StubResponse(502, Data("<html>bad gateway</html>".utf8))])
        do {
            _ = try await h.engine.getMyAffiliate(accessToken: "t", provider: "p")
            Issue.record("expected an error")
        } catch let error as AttroError {
            #expect(error.isRetryable)
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    @Test("Retryability of each error")
    func retryability() {
        #expect(AttroError.networkError(URLError(.notConnectedToInternet)).isRetryable)
        #expect(AttroError.rateLimited(retryAfter: 1).isRetryable)
        #expect(AttroError.serverError(statusCode: 503, message: nil, retryable: true).isRetryable)
        #expect(!AttroError.serverError(statusCode: 400, message: nil, retryable: false).isRetryable)
        #expect(!AttroError.unauthorized(message: nil).isRetryable)
        #expect(!AttroError.missingParameter("x").isRetryable)
        #expect(!AttroError.invalidParameter("x").isRetryable)
    }
}

@Suite("Facade", .serialized)
struct FacadeTests {
    @Test("Every network call throws notConfigured before configure")
    func notConfigured() async {
        Attro.install(nil)
        #expect(!Attro.isConfigured)
        #expect(Attro.parseUniversalLink(URL(string: "https://get-attro.com/a/demo-app/abc")!) == nil)
        await #expect(throws: AttroError.self) {
            try await Attro.handleUniversalLink(URL(string: "https://get-attro.com/a/demo-app/abc")!, appUserId: "u")
        }
        await #expect(throws: AttroError.self) { try await Attro.submitCode("X", appUserId: "u") }
        #expect(await Attro.retryPendingAttributions().isEmpty)
    }

    @Test("configure installs the configuration; parsing needs no network")
    func configured() {
        Attro.configure(Attro.Configuration(appKey: "k", publicSlug: "demo-app"))
        defer { Attro.install(nil) }
        #expect(Attro.isConfigured)
        #expect(Attro.configuration?.project.appKey == "k")
        #expect(Attro.isAttroLink(URL(string: "https://get-attro.com/a/demo-app/abc")!))
        #expect(!Attro.isAttroLink(URL(string: "https://get-attro.com/r/abc")!))
        #expect(Attro.parseUniversalLink(URL(string: "https://get-attro.com/a/demo-app/abc")!)?.code == "abc")
    }
}
