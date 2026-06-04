import Foundation

/// Errors that can occur when using the Attro SDK
public enum AttroError: Error, LocalizedError, Sendable {
    /// SDK has not been configured. Call `Attro.configure()` first.
    case notConfigured

    /// The provided URL is not a valid Attro Universal Link
    case invalidUniversalLink

    /// Network request failed
    case networkError(Error)

    /// Server returned an error response.
    ///
    /// `retryable` reflects the backend's `retryable` flag (or a 5xx fallback);
    /// the SDK uses it to decide whether to retry in-process and to persist a
    /// pending-check flag so the attribution check is retried on the next launch.
    case serverError(statusCode: Int, message: String?, retryable: Bool)

    /// Failed to decode server response
    case decodingError(Error)

    /// Required parameter was missing
    case missingParameter(String)

    /// Attribution has already been checked for this install
    case alreadyChecked

    /// Failed to persist data locally (e.g. encoding attribution for storage).
    case persistenceFailed(Error)

    /// Whether this error is transient and the request should be retried.
    ///
    /// Transport errors and server errors the backend flags as `retryable` are
    /// retryable; client (4xx) and decode errors are not.
    public var isRetryable: Bool {
        switch self {
        case .networkError:
            return true
        case .serverError(_, _, let retryable):
            return retryable
        case .notConfigured, .invalidUniversalLink, .decodingError,
             .missingParameter, .alreadyChecked, .persistenceFailed:
            return false
        }
    }

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Attro SDK has not been configured. Call Attro.configure() first."
        case .invalidUniversalLink:
            return "The URL is not a valid Attro Universal Link."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .serverError(let code, let message, _):
            if let message = message {
                return "Server error (\(code)): \(message)"
            }
            return "Server error: HTTP \(code)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .missingParameter(let param):
            return "Missing required parameter: \(param)"
        case .alreadyChecked:
            return "Attribution has already been checked for this install."
        case .persistenceFailed(let error):
            return "Failed to persist data locally: \(error.localizedDescription)"
        }
    }
}

/// Error response from the API
struct APIErrorResponse: Codable {
    let error: String
    let details: [ValidationError]?
    /// Backend hint that the failure is transient and the request may be retried
    /// (set by /api/ios/match on 5xx). Optional for endpoints that omit it.
    let retryable: Bool?

    struct ValidationError: Codable {
        let path: [String]?
        let message: String
    }
}
