import Foundation

// Request and response bodies of the device endpoints (contract §3). The
// encoded key sets are exactly the contract's; optional fields are omitted
// (not sent as null) when absent.

/// Server-side limits (zod) on the device request fields.
enum WireLimits {
    static let id = 128           // installId, requestId
    static let appUserId = 256
    static let appUserToken = 256
    static let url = 2048
    static let code = 200
}

/// `POST /api/ios/attribution/link`
struct LinkAttributionRequest: Encodable, Equatable {
    let url: String
    let installId: String
    let requestId: String
    let appUserId: String
    let appUserToken: String?
}

/// `POST /api/ios/attribution/code`
struct CodeAttributionRequest: Encodable, Equatable {
    let code: String
    let installId: String
    let requestId: String
    let appUserId: String
    let appUserToken: String?
}

/// `POST /api/ios/match`
struct MatchRequest: Encodable, Equatable {
    let installId: String
    let appUserId: String
    let appUserToken: String?
}

/// The `200` answer of every device attribution endpoint:
/// `{ attributed: true, attributionId, source, subscriberAttributes }` or
/// `{ attributed: false, reason }`.
struct AttributionResponse: Decodable {
    let attributed: Bool
    let attributionId: String?
    let source: String?
    let subscriberAttributes: [String: String]?
    let reason: String?

    struct ContractViolation: Error, CustomStringConvertible {
        let description: String
    }

    /// The outcome, validated against the contract.
    func outcome(receivedAt: Date = Date()) throws -> AttributionOutcome {
        guard attributed else {
            guard let reason, !reason.isEmpty else {
                throw ContractViolation(description: "unattributed answer without a reason")
            }
            return .notAttributed(NotAttributedReason(rawValue: reason))
        }
        guard let attributionId, !attributionId.isEmpty else {
            throw ContractViolation(description: "attributed answer without an attributionId")
        }
        guard let source, !source.isEmpty else {
            throw ContractViolation(description: "attributed answer without a source")
        }
        // The server echoes the one attribute to set. It must name the same
        // row; any other key is ignored (the SDK sets exactly one attribute).
        if let echoed = subscriberAttributes?[SubscriberAttributes.attributionIdKey],
           echoed != attributionId {
            throw ContractViolation(description: "subscriberAttributes names another row")
        }
        return .attributed(AttributionResult(
            attributionId: attributionId,
            source: AttributionSource(rawValue: source),
            receivedAt: receivedAt
        ))
    }
}
