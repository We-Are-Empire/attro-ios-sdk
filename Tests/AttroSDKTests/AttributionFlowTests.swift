import Testing
import Foundation
@testable import AttroSDK

/// Request and response shapes of the device endpoints (contract §3), against
/// a stub server serving the Attro contract fixtures.
@Suite("Deterministic attribution: Universal Links")
struct UniversalLinkFlowTests {
    let linkURL = URL(string: "https://get-attro.com/a/demo-app/abc12345?sub1=story")!

    @Test("POSTs exactly { url, installId, requestId, appUserId } with the app key")
    func requestShape() async throws {
        let h = Harness([.fixture(200, "link-attributed")])
        let outcome = try await h.engine.handleUniversalLink(linkURL, appUserId: "rc-link-user")

        let request = try #require(h.server.requests.first)
        #expect(h.server.requests.count == 1)
        #expect(request.method == "POST")
        #expect(request.url.absoluteString == "https://get-attro.com/api/ios/attribution/link")
        #expect(request.header("x-api-key") == "app_key_main")
        #expect(request.header("x-server-key") == nil)
        #expect(request.header("Content-Type") == "application/json")
        #expect(request.header("Authorization") == nil)
        #expect(request.header("User-Agent")?.hasPrefix("AttroSDK/\(Attro.sdkVersion) (") == true)

        // Same key set as the contract test's body (fixture), nothing else.
        #expect(request.jsonKeys == Set(Fixture.json("link-request").keys))
        #expect(request.json["url"] as? String == linkURL.absoluteString)
        #expect(request.json["installId"] as? String == Harness.installId)
        #expect(request.json["appUserId"] as? String == "rc-link-user")
        let requestId = try #require(request.json["requestId"] as? String)
        #expect(UUID(uuidString: requestId) != nil)

        let expectedId = Fixture.json("link-attributed")["attributionId"] as? String
        let result = try #require(outcome?.result)
        #expect(result.attributionId == expectedId)
        #expect(result.source == .universalLink)
        #expect(result.subscriberAttributes == ["attro_attribution_id": expectedId!])
        #expect(await h.engine.currentAttribution()?.attributionId == expectedId)
    }

    @Test("A link of another configured project is sent with that project's key")
    func secondProjectKey() async throws {
        let h = Harness([.fixture(200, "link-attributed")])
        _ = try await h.engine.handleUniversalLink(URL(string: "https://get-attro.com/a/second-program/xyz")!, appUserId: "u")
        #expect(h.server.requests.first?.header("x-api-key") == "app_key_second")
    }

    @Test("A custom-domain /r/<code> link is sent with its project's key")
    func customDomain() async throws {
        let h = Harness([.fixture(200, "link-attributed")])
        let outcome = try await h.engine.handleUniversalLink(URL(string: "https://go.example.com/r/abc12345")!, appUserId: "u")
        #expect(outcome?.result != nil)
        #expect(h.server.requests.first?.header("x-api-key") == "app_key_main")
        #expect(h.server.requests.first?.json["url"] as? String == "https://go.example.com/r/abc12345")
    }

    @Test("A URL that is not this app's Attro link makes no request", arguments: [
        "https://get-attro.com/r/abc12345",
        "https://get-attro.com/a/other-tenant/abc12345",
        "https://example.com/a/demo-app/abc12345",
    ])
    func notALink(_ url: String) async throws {
        let h = Harness([.fixture(200, "link-attributed")])
        let outcome = try await h.engine.handleUniversalLink(URL(string: url)!, appUserId: "u")
        #expect(outcome == nil)
        #expect(h.server.requests.isEmpty)
    }

    @Test("unknown_link is an unattributed 200 and leaves the current attribution alone")
    func unknownLink() async throws {
        let h = Harness([.fixture(200, "unknown-link")])
        let outcome = try await h.engine.handleUniversalLink(linkURL, appUserId: "u")
        #expect(outcome == .notAttributed(.unknownLink))
        #expect(await h.engine.currentAttribution() == nil)
    }

    @Test("503 { retryable: true } is retried in-process with the SAME requestId")
    func retrySameIds() async throws {
        let h = Harness([.fixture(503, "retryable-503"), .fixture(200, "link-attributed")])
        let outcome = try await h.engine.handleUniversalLink(linkURL, appUserId: "u")
        #expect(outcome?.result != nil)
        #expect(h.server.requests.count == 2)
        let ids = h.server.requests.compactMap { $0.json["requestId"] as? String }
        #expect(ids.count == 2 && ids[0] == ids[1])
        #expect(await h.storage.pendingAttempts().isEmpty)
    }

    @Test("A transient failure is kept and resent later with the same ids")
    func durableRetry() async throws {
        let h = Harness([.fixture(503, "retryable-503")])
        await #expect(throws: AttroError.self) {
            try await h.engine.handleUniversalLink(linkURL, appUserId: "rc-user")
        }
        #expect(h.server.requests.count == 3) // first try + 2 retries
        let pending = await h.storage.pendingAttempts()
        #expect(pending.count == 1)
        #expect(pending.first?.appUserId == "rc-user")

        h.server.enqueue(.fixture(200, "link-attributed"))
        // Drain the 503 script entry so the next request gets the 200.
        let outcomes = await retryUntilAnswered(h)
        #expect(outcomes.first?.result?.source == .universalLink)
        let ids = Set(h.server.requests.compactMap { $0.json["requestId"] as? String })
        #expect(ids.count == 1)
        #expect(h.server.requests.last?.json["appUserId"] as? String == "rc-user")
        #expect(await h.storage.pendingAttempts().isEmpty)
    }

    /// The stub replays its last response forever; the enqueued 200 follows
    /// the 503 once the 503 was consumed.
    private func retryUntilAnswered(_ h: Harness) async -> [AttributionOutcome] {
        for _ in 0..<3 {
            let outcomes = await h.engine.retryPendingAttributions()
            if !outcomes.isEmpty { return outcomes }
        }
        return []
    }

    @Test("Opening the same link again while it is pending reuses its requestId")
    func reopenReusesId() async throws {
        let h = Harness([.fixture(429, "rate-limited-429", headers: ["Retry-After": "42"])])
        await #expect(throws: AttroError.self) {
            try await h.engine.handleUniversalLink(linkURL, appUserId: "u")
        }
        h.server.enqueue(.fixture(200, "link-attributed"))
        _ = try? await h.engine.handleUniversalLink(linkURL, appUserId: "u")
        _ = try? await h.engine.handleUniversalLink(linkURL, appUserId: "u")
        let ids = Set(h.server.requests.compactMap { $0.json["requestId"] as? String })
        #expect(ids.count == 1)
    }

    @Test("429 surfaces Retry-After, is not retried in-process, and is kept pending")
    func rateLimited() async throws {
        let h = Harness([.fixture(429, "rate-limited-429", headers: ["Retry-After": "42"])])
        do {
            _ = try await h.engine.handleUniversalLink(linkURL, appUserId: "u")
            Issue.record("expected a rate-limit error")
        } catch AttroError.rateLimited(let retryAfter) {
            #expect(retryAfter == 42)
        }
        #expect(h.server.requests.count == 1)
        #expect(await h.storage.pendingAttempts().count == 1)
    }

    @Test("401 is not retried and not kept")
    func unauthorized() async throws {
        let h = Harness([.fixture(401, "unauthorized-app-key-401")])
        do {
            _ = try await h.engine.handleUniversalLink(linkURL, appUserId: "u")
            Issue.record("expected 401")
        } catch AttroError.unauthorized(let message) {
            #expect(message == "Invalid or missing x-api-key")
        }
        #expect(h.server.requests.count == 1)
        #expect(await h.storage.pendingAttempts().isEmpty)
    }

    @Test("400 is not retried")
    func validationError() async throws {
        let h = Harness([StubResponse(400, Data(#"{"error":"Validation failed"}"#.utf8))])
        await #expect(throws: AttroError.self) {
            try await h.engine.handleUniversalLink(linkURL, appUserId: "u")
        }
        #expect(h.server.requests.count == 1)
        #expect(await h.storage.pendingAttempts().isEmpty)
    }

    @Test("appUserId is required and bounded; no request is made otherwise")
    func appUserIdValidation() async throws {
        let h = Harness([.fixture(200, "link-attributed")])
        await #expect(throws: AttroError.self) {
            try await h.engine.handleUniversalLink(linkURL, appUserId: "  ")
        }
        await #expect(throws: AttroError.self) {
            try await h.engine.handleUniversalLink(linkURL, appUserId: String(repeating: "u", count: 257))
        }
        #expect(h.server.requests.isEmpty)
    }

    @Test("An attributed answer without an attributionId is a contract violation")
    func malformedAnswer() async throws {
        let h = Harness([StubResponse(200, Data(#"{"attributed":true,"source":"universal_link"}"#.utf8))])
        do {
            _ = try await h.engine.handleUniversalLink(linkURL, appUserId: "u")
            Issue.record("expected a decoding error")
        } catch AttroError.decodingError {
        }
        #expect(await h.engine.currentAttribution() == nil)
    }

    @Test("User-token mode sends appUserToken obtained for exactly that appUserId")
    func userToken() async throws {
        let seen = LockedBox<[String]>([])
        let config = Harness.configuration(appUserTokenProvider: { appUserId in
            seen.mutate { $0.append(appUserId) }
            return "tok-for-\(appUserId)"
        })
        let h = Harness([.fixture(200, "link-attributed")], configuration: config)
        _ = try await h.engine.handleUniversalLink(linkURL, appUserId: "rc-user")
        let body = try #require(h.server.requests.first?.json)
        #expect(Set(body.keys) == ["url", "installId", "requestId", "appUserId", "appUserToken"])
        #expect(body["appUserToken"] as? String == "tok-for-rc-user")
        #expect(seen.value == ["rc-user"])
    }

    @Test("A 401 for a bad appUserToken is surfaced, not retried")
    func badToken() async throws {
        let config = Harness.configuration(appUserTokenProvider: { _ in "expired" })
        let h = Harness([.fixture(401, "unauthorized-token-401")], configuration: config)
        await #expect(throws: AttroError.self) {
            try await h.engine.handleUniversalLink(linkURL, appUserId: "u")
        }
        #expect(h.server.requests.count == 1)
    }
}

@Suite("Deterministic attribution: typed codes")
struct TypedCodeFlowTests {
    @Test("POSTs exactly { code, installId, requestId, appUserId } with the trimmed code")
    func requestShape() async throws {
        let h = Harness([.fixture(200, "code-attributed")])
        let outcome = try await h.engine.submitCode("  appcode42 ", appUserId: "rc-typed-user", publicSlug: nil)

        let request = try #require(h.server.requests.first)
        #expect(request.url.path == "/api/ios/attribution/code")
        #expect(request.header("x-api-key") == "app_key_main")
        #expect(request.jsonKeys == ["code", "installId", "requestId", "appUserId"])
        #expect(request.json["code"] as? String == "appcode42")
        #expect(request.json["appUserId"] as? String == "rc-typed-user")
        #expect(outcome.result?.source == .code)
        #expect(await h.engine.currentAttribution()?.source == .code)
    }

    @Test("unknown_code is an unattributed 200")
    func unknownCode() async throws {
        let h = Harness([.fixture(200, "unknown-code")])
        let outcome = try await h.engine.submitCode("NOPE-NOT-A-CODE", appUserId: "u", publicSlug: nil)
        #expect(outcome == .notAttributed(.unknownCode))
    }

    @Test("A code for another configured project uses that project's key")
    func otherProject() async throws {
        let h = Harness([.fixture(200, "code-attributed")])
        _ = try await h.engine.submitCode("X", appUserId: "u", publicSlug: "second-program")
        #expect(h.server.requests.first?.header("x-api-key") == "app_key_second")
    }

    @Test("Empty, over-long or unroutable codes make no request")
    func validation() async throws {
        let h = Harness([.fixture(200, "code-attributed")])
        await #expect(throws: AttroError.self) { try await h.engine.submitCode("   ", appUserId: "u", publicSlug: nil) }
        await #expect(throws: AttroError.self) {
            try await h.engine.submitCode(String(repeating: "c", count: 201), appUserId: "u", publicSlug: nil)
        }
        await #expect(throws: AttroError.self) { try await h.engine.submitCode("X", appUserId: "u", publicSlug: "nope") }
        #expect(h.server.requests.isEmpty)
    }

    @Test("A newer deterministic answer replaces the current attribution")
    func lastDeterministicWins() async throws {
        let h = Harness([.fixture(200, "link-attributed"), .fixture(200, "code-attributed")])
        _ = try await h.engine.handleUniversalLink(URL(string: "https://get-attro.com/a/demo-app/abc")!, appUserId: "u")
        _ = try await h.engine.submitCode("X", appUserId: "u", publicSlug: nil)
        #expect(await h.engine.currentAttribution()?.source == .code)
    }
}

@Suite("Probabilistic match (opt-in)")
struct ProbabilisticMatchTests {
    @Test("Off by default: no request at all")
    func offByDefault() async throws {
        let h = Harness([.fixture(200, "match-attributed")])
        let outcome = try await h.engine.matchInstall(appUserId: "u")
        #expect(outcome == nil)
        #expect(h.server.requests.isEmpty)
    }

    @Test("Opted in: POSTs exactly { installId, appUserId } with the WebKit User-Agent")
    func requestShape() async throws {
        let h = Harness([.fixture(200, "match-attributed")], configuration: Harness.configuration(probabilisticMatching: true))
        let outcome = try await h.engine.matchInstall(appUserId: "rc-user")

        let request = try #require(h.server.requests.first)
        #expect(request.url.path == "/api/ios/match")
        #expect(request.header("x-api-key") == "app_key_main")
        #expect(request.header("User-Agent") == Harness.webKitUA)
        #expect(request.jsonKeys == ["installId", "appUserId"])
        #expect(outcome?.result?.source == .probabilistic)
        #expect(await h.engine.currentAttribution()?.source == .probabilistic)

        // Matched at most once per install.
        #expect(try await h.engine.matchInstall(appUserId: "rc-user") == nil)
        #expect(h.server.requests.count == 1)
    }

    @Test("not_enabled is definitive: never asked again")
    func notEnabled() async throws {
        let h = Harness([.fixture(200, "not-enabled")], configuration: Harness.configuration(probabilisticMatching: true))
        #expect(try await h.engine.matchInstall(appUserId: "u") == .notAttributed(.notEnabled))
        #expect(try await h.engine.matchInstall(appUserId: "u") == nil)
        #expect(h.server.requests.count == 1)
    }

    @Test("A transient failure is asked again later")
    func retryLater() async throws {
        let h = Harness([.fixture(503, "retryable-503")], configuration: Harness.configuration(probabilisticMatching: true))
        await #expect(throws: AttroError.self) { try await h.engine.matchInstall(appUserId: "u") }
        let afterFailure = h.server.requests.count
        h.server.enqueue(.fixture(200, "match-attributed"))
        _ = try? await h.engine.matchInstall(appUserId: "u")
        #expect(h.server.requests.count > afterFailure)
    }

    @Test("Deterministic first: skipped once a link or code attributed")
    func skippedAfterDeterministic() async throws {
        let h = Harness(
            [.fixture(200, "link-attributed"), .fixture(200, "match-attributed")],
            configuration: Harness.configuration(probabilisticMatching: true)
        )
        _ = try await h.engine.handleUniversalLink(URL(string: "https://get-attro.com/a/demo-app/abc")!, appUserId: "u")
        #expect(try await h.engine.matchInstall(appUserId: "u") == nil)
        #expect(h.server.requests.count == 1)
    }

    @Test("A probabilistic answer never replaces a deterministic attribution")
    func neverOverridesDeterministic() async {
        let h = Harness()
        let link = AttributionResult(attributionId: "link-row", source: .universalLink)
        let guess = AttributionResult(attributionId: "guess-row", source: .probabilistic)
        #expect(await h.storage.recordAttribution(link))
        #expect(await h.storage.recordAttribution(guess) == false)
        #expect(await h.storage.lastAttribution?.attributionId == "link-row")

        let fresh = Harness()
        #expect(await fresh.storage.recordAttribution(guess))
        #expect(await fresh.storage.recordAttribution(link))
        #expect(await fresh.storage.lastAttribution?.attributionId == "link-row")
    }

    @Test("Without a WebKit User-Agent the SDK sends its own, never a forged browser one")
    func noWebKit() async throws {
        let h = Harness(
            [.fixture(200, "not-enabled")],
            configuration: Harness.configuration(probabilisticMatching: true),
            webKitUA: nil
        )
        _ = try await h.engine.matchInstall(appUserId: "u")
        #expect(h.server.requests.first?.header("User-Agent")?.hasPrefix("AttroSDK/") == true)
    }

    @Test("The WebKit User-Agent is cached per OS version")
    func cachedUserAgent() async {
        let h = Harness()
        await h.storage.setWebKitUserAgent("UA-17", osVersion: "17_5")
        #expect(await h.storage.webKitUserAgent(osVersion: "17_5") == "UA-17")
        #expect(await h.storage.webKitUserAgent(osVersion: "18_0") == nil)
    }
}

/// A tiny lock-protected box for values captured by @Sendable closures.
final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ value: T) { stored = value }
    var value: T {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
    func mutate(_ body: (inout T) -> Void) {
        lock.lock()
        body(&stored)
        lock.unlock()
    }
}
