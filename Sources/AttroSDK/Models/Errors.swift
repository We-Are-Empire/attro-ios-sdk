import Foundation

/// Errors that can occur when using the Attro SDK
public enum AttroError: Error, LocalizedError, Sendable {
    /// SDK has not been configured. Call `Attro.configure()` first.
    case notConfigured

    /// Network request failed (offline, timeout, DNS). Retryable.
    case networkError(Error)

    /// `401`: a missing or unknown app key, or (user-token mode) a missing,
    /// expired or foreign `appUserToken`. Do not retry with the same token.
    case unauthorized(message: String?)

    /// `429`: rate limited. `retryAfter` is the server's `Retry-After`, in
    /// seconds, when it sent one. Retry no sooner than that, with the same ids.
    case rateLimited(retryAfter: TimeInterval?)

    /// Any other non-2xx answer. `retryable` is the backend's `retryable` flag
    /// (a `503 { "retryable": true }` is a server fault to retry with the same
    /// ids), falling back to "5xx is retryable, 4xx is not".
    case serverError(statusCode: Int, message: String?, retryable: Bool)

    /// The response did not match the contract (including a Money object whose
    /// fields disagree, or a float where money must be exact).
    case decodingError(Error)

    /// A required parameter was missing or empty.
    case missingParameter(String)

    /// A parameter is outside what the contract accepts (for example longer
    /// than the server allows). Fix the input; a retry cannot succeed.
    case invalidParameter(String)

    /// The configured `appUserTokenProvider` failed to produce a token.
    case appUserTokenUnavailable(Error)

    /// RevenueCat is not configured (`Purchases.configure` has not run), so the
    /// RevenueCat app user id is unknown. Only thrown by `AttroRevenueCat`.
    case revenueCatNotConfigured

    /// Failed to persist data locally.
    case persistenceFailed(Error)

    /// Whether this error is transient and the same request may be retried
    /// later with the same ids.
    public var isRetryable: Bool {
        switch self {
        case .networkError, .rateLimited, .appUserTokenUnavailable:
            return true
        case .serverError(_, _, let retryable):
            return retryable
        case .notConfigured, .unauthorized, .decodingError, .missingParameter,
             .invalidParameter, .revenueCatNotConfigured, .persistenceFailed:
            return false
        }
    }

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Attro SDK has not been configured. Call Attro.configure() first."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .unauthorized(let message):
            return "Unauthorized (401): \(message ?? "invalid app key or appUserToken")"
        case .rateLimited(let retryAfter):
            if let retryAfter {
                return "Rate limited (429); retry after \(Int(retryAfter)) seconds."
            }
            return "Rate limited (429)."
        case .serverError(let code, let message, _):
            if let message {
                return "Server error (\(code)): \(message)"
            }
            return "Server error: HTTP \(code)"
        case .decodingError(let error):
            return "Failed to decode response: \(error)"
        case .missingParameter(let param):
            return "Missing required parameter: \(param)"
        case .invalidParameter(let param):
            return "Invalid parameter: \(param)"
        case .appUserTokenUnavailable(let error):
            return "The appUserTokenProvider failed: \(error.localizedDescription)"
        case .revenueCatNotConfigured:
            return "RevenueCat is not configured. Call Purchases.configure() before Attro."
        case .persistenceFailed(let error):
            return "Failed to persist data locally: \(error.localizedDescription)"
        }
    }
}

/// Error response from the API (the contract's `device-error.schema.json`).
struct APIErrorResponse: Decodable {
    let error: String?
    /// Machine-readable code, where the server defines one
    /// (`SDK_UPGRADE_REQUIRED`, `INVALID_INPUT`).
    let code: String?
    /// Backend hint that the failure is transient and the request may be
    /// retried with the same ids (`503 { "retryable": true }`).
    let retryable: Bool?
    /// Seconds to wait, echoed in the body of a `429`.
    let retryAfter: Int?
    /// `426`: the oldest SDK version the server still serves.
    let minimumVersion: String?
}
