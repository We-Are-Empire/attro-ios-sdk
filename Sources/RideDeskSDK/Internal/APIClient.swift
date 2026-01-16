import Foundation

/// Internal HTTP client for RideDesk API calls
actor APIClient {
    private let baseURL: URL
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(baseURL: URL) {
        self.baseURL = baseURL

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)

        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    /// Make a POST request to the API
    func post<T: Decodable, B: Encodable>(
        _ path: String,
        body: B
    ) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("RideDeskSDK/1.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RideDeskError.networkError(
                NSError(domain: "RideDeskSDK", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Invalid response type"
                ])
            )
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let message = try? decoder.decode(APIErrorResponse.self, from: data).error
            throw RideDeskError.serverError(
                statusCode: httpResponse.statusCode,
                message: message
            )
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw RideDeskError.decodingError(error)
        }
    }

    /// Make a GET request to the API
    func get<T: Decodable>(_ path: String) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("RideDeskSDK/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RideDeskError.networkError(
                NSError(domain: "RideDeskSDK", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Invalid response type"
                ])
            )
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let message = try? decoder.decode(APIErrorResponse.self, from: data).error
            throw RideDeskError.serverError(
                statusCode: httpResponse.statusCode,
                message: message
            )
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw RideDeskError.decodingError(error)
        }
    }

    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw RideDeskError.networkError(error)
        }
    }
}
