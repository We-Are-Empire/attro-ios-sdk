import Foundation

/// Internal HTTP client for Attro API calls
actor APIClient {
    private let baseURL: URL
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Maximum number of in-process attempts for a retryable failure (the first
    /// try plus up to `maxRetries` retries). Cross-launch durability is handled
    /// separately by the pending-check flag in Attro/AttroStorage.
    private let maxRetries: Int

    /// Base delay (seconds) for the exponential backoff between retries.
    private let retryBaseDelay: Double

    init(
        baseURL: URL,
        session: URLSession? = nil,
        maxRetries: Int = 2,
        retryBaseDelay: Double = 0.5
    ) {
        self.baseURL = baseURL

        if let session = session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 30
            config.timeoutIntervalForResource = 60
            self.session = URLSession(configuration: config)
        }

        self.maxRetries = max(0, maxRetries)
        self.retryBaseDelay = max(0, retryBaseDelay)

        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    /// Make a POST request to the API.
    ///
    /// - Parameters:
    ///   - path: API path appended to the base URL.
    ///   - body: Encodable request body.
    ///   - userAgent: User-Agent header to send. Pass the real device
    ///     User-Agent (see `DeviceInfo.currentUserAgent`) so the backend matcher
    ///     can award browser-family confidence points.
    ///   - apiKey: Optional server-to-server key sent as `x-api-key` — required by
    ///     the `/api/ios/referral/*` endpoints to prove the caller is the app.
    ///   - bearerToken: Optional upstream access token sent as
    ///     `Authorization: Bearer <token>` — identifies WHICH user (the referral
    ///     endpoints derive the affiliate from the verified token subject).
    func post<T: Decodable, B: Encodable>(
        _ path: String,
        body: B,
        userAgent: String = DeviceInfo.defaultUserAgent,
        apiKey: String? = nil,
        bearerToken: String? = nil
    ) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let apiKey = apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        }
        if let bearerToken = bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try encoder.encode(body)

        return try await send(request)
    }

    /// Make a GET request to the API
    func get<T: Decodable>(
        _ path: String,
        userAgent: String = DeviceInfo.defaultUserAgent
    ) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        return try await send(request)
    }

    /// Execute a request with bounded retry on retryable failures.
    ///
    /// A failure is retried (up to `maxRetries` times, with exponential backoff)
    /// only when it is retryable: a transport error, or a 5xx response that the
    /// backend flags with `retryable: true` (the contract for /api/ios/match).
    /// Non-retryable failures (4xx, decode errors, or a 5xx without the flag)
    /// throw immediately so the caller does not loop on a permanent error.
    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        var attempt = 0
        while true {
            do {
                return try await execute(request)
            } catch let error as AttroError {
                if error.isRetryable && attempt < maxRetries {
                    attempt += 1
                    // Exponential backoff: base * 2^(attempt-1).
                    let delay = retryBaseDelay * pow(2.0, Double(attempt - 1))
                    if delay > 0 {
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    }
                    continue
                }
                throw error
            }
        }
    }

    /// Perform a single request attempt and decode the response.
    private func execute<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AttroError.networkError(
                NSError(domain: "AttroSDK", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Invalid response type"
                ])
            )
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let errorBody = try? decoder.decode(APIErrorResponse.self, from: data)
            // Honor the backend's explicit `retryable` flag. When absent, fall
            // back to "5xx is retryable, 4xx is not" so transient server
            // failures are retried but client errors are not.
            let retryable = errorBody?.retryable ?? (httpResponse.statusCode >= 500)
            throw AttroError.serverError(
                statusCode: httpResponse.statusCode,
                message: errorBody?.error,
                retryable: retryable
            )
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw AttroError.decodingError(error)
        }
    }

    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            // Transport-level failures (offline, timeout, DNS) are transient and
            // therefore retryable.
            throw AttroError.networkError(error)
        }
    }
}
