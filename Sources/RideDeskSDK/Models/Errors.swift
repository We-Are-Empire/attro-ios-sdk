import Foundation

/// Errors that can occur when using the RideDesk SDK
public enum RideDeskError: Error, LocalizedError, Sendable {
    /// SDK has not been configured. Call `RideDesk.configure()` first.
    case notConfigured

    /// The provided URL is not a valid RideDesk Universal Link
    case invalidUniversalLink

    /// Network request failed
    case networkError(Error)

    /// Server returned an error response
    case serverError(statusCode: Int, message: String?)

    /// Failed to decode server response
    case decodingError(Error)

    /// Required parameter was missing
    case missingParameter(String)

    /// Attribution has already been checked for this install
    case alreadyChecked

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "RideDesk SDK has not been configured. Call RideDesk.configure() first."
        case .invalidUniversalLink:
            return "The URL is not a valid RideDesk Universal Link."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .serverError(let code, let message):
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
        }
    }
}

/// Error response from the API
struct APIErrorResponse: Codable {
    let error: String
    let details: [ValidationError]?

    struct ValidationError: Codable {
        let path: [String]?
        let message: String
    }
}
