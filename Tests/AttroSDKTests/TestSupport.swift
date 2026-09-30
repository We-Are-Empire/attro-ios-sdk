import Foundation
@testable import AttroSDK

// MARK: - Fixtures

enum Fixture {
    /// The raw bytes of `Fixtures/<name>.json` (copied from the Attro contract
    /// tests, see Fixtures/README.md).
    static func data(_ name: String) -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
              let data = try? Data(contentsOf: url) else {
            fatalError("Missing fixture \(name).json")
        }
        return data
    }

    static func json(_ name: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: data(name))) as? [String: Any] ?? [:]
    }
}

// MARK: - Stub HTTP

/// One scripted response.
struct StubResponse: Sendable {
    let status: Int
    let headers: [String: String]
    let body: Data

    init(_ status: Int, _ body: Data, headers: [String: String] = [:]) {
        self.status = status
        self.body = body
        self.headers = headers
    }

    static func fixture(_ status: Int, _ name: String, headers: [String: String] = [:]) -> StubResponse {
        StubResponse(status, Fixture.data(name), headers: headers)
    }
}

/// A recorded request, with its body (URLProtocol moves it to a stream).
struct RecordedRequest: Sendable {
    let url: URL
    let method: String
    let headers: [String: String]
    let body: Data

    func header(_ name: String) -> String? {
        headers.first { $0.key.lowercased() == name.lowercased() }?.value
    }

    var json: [String: Any] {
        (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
    }

    var jsonKeys: Set<String> { Set(json.keys) }
}

/// A scripted server for one test. Each server has its own URLSession tagged
/// with a header, so tests using different servers can run in parallel.
final class StubServer: @unchecked Sendable {
    static let sessionHeader = "X-Stub-Server"

    let id = UUID().uuidString
    private let lock = NSLock()
    private var script: [StubResponse]
    private var recorded: [RecordedRequest] = []

    init(_ script: [StubResponse]) {
        self.script = script
        StubURLProtocol.register(self)
    }

    deinit { StubURLProtocol.unregister(id) }

    func enqueue(_ responses: StubResponse...) {
        lock.lock()
        script.append(contentsOf: responses)
        lock.unlock()
    }

    var requests: [RecordedRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    var session: URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        config.httpAdditionalHeaders = [Self.sessionHeader: id]
        return URLSession(configuration: config)
    }

    fileprivate func respond(to request: RecordedRequest) -> StubResponse {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(request)
        guard !script.isEmpty else { return StubResponse(599, Data("unscripted request".utf8)) }
        return script.count == 1 ? script[0] : script.removeFirst()
    }
}

final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var servers: [String: StubServer] = [:]

    static func register(_ server: StubServer) {
        lock.lock()
        servers[server.id] = server
        lock.unlock()
    }

    static func unregister(_ id: String) {
        lock.lock()
        servers[id] = nil
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let headers = request.allHTTPHeaderFields ?? [:]
        let serverId = headers.first { $0.key.lowercased() == StubServer.sessionHeader.lowercased() }?.value
        Self.lock.lock()
        let server = serverId.flatMap { Self.servers[$0] }
        Self.lock.unlock()

        let recorded = RecordedRequest(
            url: request.url!,
            method: request.httpMethod ?? "GET",
            headers: headers.filter { $0.key.lowercased() != StubServer.sessionHeader.lowercased() },
            body: Self.body(of: request)
        )
        let reply = server?.respond(to: recorded) ?? StubResponse(599, Data())
        let response = HTTPURLResponse(
            url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

// MARK: - Engine harness

struct StubWebKitUserAgent: WebKitUserAgentProviding {
    let value: String?
    @MainActor func webKitUserAgent() async -> String? { value }
}

/// An engine wired to a stub server and scratch UserDefaults (removed on
/// deinit).
final class Harness: @unchecked Sendable {
    static let webKitUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"
    static let installId = "inst-0001"

    let server: StubServer
    let suiteName = "attro-sdk-tests-\(UUID().uuidString)"
    let defaults: UserDefaults
    let storage: AttroStorage
    let engine: AttroEngine

    init(
        _ script: [StubResponse] = [],
        configuration: Attro.Configuration = Harness.configuration(),
        webKitUA: String? = Harness.webKitUA
    ) {
        server = StubServer(script)
        defaults = UserDefaults(suiteName: suiteName)!
        storage = AttroStorage(defaults: defaults)
        engine = AttroEngine(
            configuration: configuration,
            client: APIClient(baseURL: configuration.baseURL, session: server.session, maxRetries: 2, retryBaseDelay: 0),
            storage: storage,
            installIds: FixedInstallIdStore(Harness.installId),
            webKitUserAgent: StubWebKitUserAgent(value: webKitUA)
        )
    }

    deinit { defaults.removePersistentDomain(forName: suiteName) }

    static func configuration(
        probabilisticMatching: Bool = false,
        appUserTokenProvider: Attro.AppUserTokenProvider? = nil
    ) -> Attro.Configuration {
        Attro.Configuration(
            project: Attro.Project(appKey: "app_key_main", publicSlug: "demo-app", customDomains: ["go.example.com"]),
            additionalProjects: [Attro.Project(appKey: "app_key_second", publicSlug: "second-program")],
            baseURL: URL(string: "https://get-attro.com")!,
            probabilisticMatching: probabilisticMatching,
            appUserTokenProvider: appUserTokenProvider
        )
    }
}
