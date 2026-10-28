import Testing
import Foundation
@testable import AttroSDK

/// The RevenueCat attribute contract (contract §4): exactly one attribute,
/// `attro_attribution_id`, with a key RevenueCat accepts.
@Suite("RevenueCat subscriber attributes")
struct SubscriberAttributeTests {
    @Test("The key is attro_attribution_id and follows RevenueCat's rules")
    func key() {
        #expect(Attro.attributionAttributeKey == "attro_attribution_id")
        #expect(SubscriberAttributes.attributionIdKey == "attro_attribution_id")
        #expect(SubscriberAttributes.isValidKey(Attro.attributionAttributeKey))
        #expect(!Attro.attributionAttributeKey.hasPrefix("$"))
    }

    @Test("An attribution sets exactly one attribute: its row id")
    func exactlyOne() {
        let result = AttributionResult(attributionId: "6f1c0f0e-8f7a-4c1e-9c55-2b6a1c3d4e5f", source: .universalLink)
        #expect(result.subscriberAttributes == ["attro_attribution_id": "6f1c0f0e-8f7a-4c1e-9c55-2b6a1c3d4e5f"])
        #expect(result.subscriberAttributes.keys.allSatisfy(SubscriberAttributes.isValidKey))
    }

    @Test("Keys RevenueCat refuses are invalid", arguments: [
        "$rd_click_id",                                   // v1 key: `$` is reserved by RevenueCat
        "$rd_project_id",
        "$attributionId",
        "",
        "has space",
        "dot.key",
        "slash/key",
        "émoji",
        String(repeating: "k", count: 41),                // over 40 characters
    ])
    func invalidKeys(_ key: String) {
        #expect(!SubscriberAttributes.isValidKey(key))
    }

    @Test("Keys within the rules are valid", arguments: [
        "attro_attribution_id",
        "a",
        "A-b_9",
        String(repeating: "k", count: 40),
    ])
    func validKeys(_ key: String) {
        #expect(SubscriberAttributes.isValidKey(key))
    }

    @Test("The server's echoed attributes must name the same row")
    func echoMismatch() throws {
        let wire = #"{"attributed":true,"attributionId":"a","source":"code","subscriberAttributes":{"attro_attribution_id":"b"}}"#
        let response = try JSONDecoder().decode(AttributionResponse.self, from: Data(wire.utf8))
        #expect(throws: (any Error).self) { try response.outcome() }
    }

    @Test("Unknown server attribute keys are ignored, never applied")
    func extraKeysIgnored() throws {
        let wire = #"{"attributed":true,"attributionId":"a","source":"code","subscriberAttributes":{"attro_attribution_id":"a","$rd_click_id":"x"}}"#
        let response = try JSONDecoder().decode(AttributionResponse.self, from: Data(wire.utf8))
        let result = try #require(try response.outcome().result)
        #expect(result.subscriberAttributes == ["attro_attribution_id": "a"])
    }
}
