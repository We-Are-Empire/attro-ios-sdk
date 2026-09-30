import Foundation

/// Internal HTTP client for Attro API calls
actor APIClient {
    private let baseURL: URL
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Maximum number of in-process retries of a retryable failure (transport
    /// error or a retryable 5xx). The retried request is byte-identical, so it
    /// carries the same `requestId` and the server replays the first answer.
    private let maxRetries: Int

    /// Base delay (seconds) for the exponential backoff between retries.
    private let retryBaseDelay: TimeInterval

    init(
        baseURL: URL,
        session: URLSession? = nil,
        maxRetries: Int = 2,
        retryBaseDelay: TimeInterval = 0.5
    ) {
        self.baseURL = baseURL
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 30
            config.timeoutIntervalForResource = 60
            config.httpCookieAcceptPolicy = .never
            config.httpShouldSetCookies = false
            config.urlCache = nil
            self.session = URLSession(configuration: config)
        }
        self.maxRetries = max(0, maxRetries)
        self.retryBaseDelay = max(0, retryBaseDelay)
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    /// POST a JSON body and decode the JSON answer.
    ///
    /// - Parameters:
    ///   - apiKey: the project's app key, sent as `x-api-key`.
    ///   - userAgent: the `User-Agent` header.
    ///   - bearerToken: an upstream access token, sent as
    ///     `Authorization: Bearer <token>` (refer-a-friend endpoints only).
    func post<T: Decodable, B: Encodable>(
        _ path: String,
        body: B,
        apiKey: String,
        userAgent: String,
        bearerToken: String? = nil
    ) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try encoder.encode(body)
        return try await send(request)
    }

    /// Execute with bounded in-process retry. Only transport errors and
    /// retryable 5xx answers are retried here; a `429` is surfaced at once
    /// (its `Retry-After` can be long) and retried later by the caller.
    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        var attempt = 0
        while true {
            do {
                return try await execute(request)
            } catch let error as AttroError {
                let retryInProcess: Bool
                switch error {
                case .networkError: retryInProcess = true
                case .serverError(_, _, let retryable): retryInProcess = retryable
                default: retryInProcess = false
                }
                guard retryInProcess, attempt < maxRetries else { throw error }
                attempt += 1
                let delay = retryBaseDelay * pow(2.0, Double(attempt - 1))
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
    }

    /// Perform a single request attempt and decode the response.
    private func execute<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AttroError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AttroError.networkError(URLError(.badServerResponse))
        }

        guard 200..<300 ~= http.statusCode else {
            let body = try? decoder.decode(APIErrorResponse.self, from: data)
            switch http.statusCode {
            case 401:
                throw AttroError.unauthorized(message: body?.error)
            case 429:
                let header = http.value(forHTTPHeaderField: "Retry-After").flatMap { TimeInterval($0) }
                throw AttroError.rateLimited(retryAfter: header ?? body?.retryAfter.map(TimeInterval.init))
            default:
                throw AttroError.serverError(
                    statusCode: http.statusCode,
                    message: body?.error,
                    retryable: body?.retryable ?? (http.statusCode >= 500)
                )
            }
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw AttroError.decodingError(error)
        }
    }
}
