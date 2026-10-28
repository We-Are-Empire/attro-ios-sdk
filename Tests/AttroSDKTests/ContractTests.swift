import Testing
import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif
@testable import AttroSDK

// The SDK against the vendored device contract (Contract/, copied from
// Attro's docs/contracts/device/ by scripts/sync-contract.sh): the copy is
// intact, every fixture and every request the SDK sends matches the schema
// the contract names for it, every path the SDK calls is a canonical iOS
// endpoint, and every request identifies the SDK (X-Attro-SDK).

/// The vendored contract files.
enum Contract {
    static let directory = "Contract"
    static let checksumList = "CHECKSUMS.sha256"

    static func url(_ file: String) -> URL {
        let name = (file as NSString).deletingPathExtension
        let ext = (file as NSString).pathExtension
        guard let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: directory) else {
            fatalError("Missing vendored contract file \(file): run scripts/sync-contract.sh <attro checkout>")
        }
        return url
    }

    static func data(_ file: String) -> Data {
        guard let data = try? Data(contentsOf: url(file)) else { fatalError("Unreadable contract file \(file)") }
        return data
    }

    static func json(_ file: String) -> JSONValue {
        guard let value = try? JSONValue.parse(data(file)) else { fatalError("Contract file \(file) is not JSON") }
        return value
    }

    /// Every file in Contract/, sorted.
    static var files: [String] {
        let dir = url("contract.json").deletingLastPathComponent()
        return ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
    }

    static var manifest: JSONValue { json("contract.json") }

    /// The endpoint whose canonical path is `path` (aliases do not count).
    static func endpoint(_ path: String) -> JSONValue? {
        manifest["endpoints"]?.arrayValue?.first { $0["path"]?.stringValue == path }
    }

    static func requestSchema(_ path: String) -> JSONValue? {
        endpoint(path)?["request"]?.stringValue.map { json($0) }
    }

    static func responseSchema(_ path: String, status: Int) -> JSONValue? {
        endpoint(path)?["responses"]?[String(status)]?.stringValue.map { json($0) }
    }

    /// The lines of CHECKSUMS.sha256 (`<sha256>  <file>`).
    static var checksums: [(hex: String, file: String)] {
        String(decoding: data(checksumList), as: UTF8.self)
            .split(separator: "\n")
            .map { line in
                let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                return (hex: String(parts.first ?? ""), file: String(parts.last ?? ""))
            }
    }
}

/// One entry of Fixtures/fixtures.json: the endpoint a fixture belongs to,
/// and either the status it answers or `request: true` for a request body.
struct FixtureEntry: Decodable {
    let endpoint: String
    let status: Int?
    let request: Bool?
}

/// `"2.0.0"` -> `[2, 0, 0]`.
private func versionParts(_ version: String) -> [Int] {
    version.split(separator: ".").map { Int($0) ?? -1 }
}

/// The SDK's device calls, each against a stub serving a contract fixture.
enum ContractCall: String, CaseIterable, Sendable {
    case link, linkWithUserToken, code, match, myAffiliate, referralMe

    var fixture: String {
        switch self {
        case .link, .linkWithUserToken: return "link-attributed"
        case .code: return "code-attributed"
        case .match: return "match-attributed"
        case .myAffiliate: return "my-affiliate-usd"
        case .referralMe: return "referral-me"
        }
    }

    var configuration: Attro.Configuration {
        let tokenProvider: Attro.AppUserTokenProvider?
        if self == .linkWithUserToken {
            tokenProvider = { _ in "user-token-123" }
        } else {
            tokenProvider = nil
        }
        return Harness.configuration(probabilisticMatching: self == .match, appUserTokenProvider: tokenProvider)
    }

    func perform(on engine: AttroEngine) async throws {
        switch self {
        case .link, .linkWithUserToken:
            _ = try await engine.handleUniversalLink(
                URL(string: "https://get-attro.com/a/demo-app/abc12345?sub1=story")!, appUserId: "rc-link-user"
            )
        case .code:
            _ = try await engine.submitCode("appcode42", appUserId: "rc-typed-user", publicSlug: nil)
        case .match:
            _ = try await engine.matchInstall(appUserId: "rc-user")
        case .myAffiliate:
            _ = try await engine.getMyAffiliate(accessToken: "upstream-token", provider: "demo-idp")
        case .referralMe:
            _ = try await engine.getReferralProgram(accessToken: "upstream-token", provider: "demo-idp")
        }
    }
}

@Suite("Device contract (vendored copy)")
struct ContractTests {
    #if canImport(CryptoKit)
    @Test("The copy holds exactly the files its checksum list names, with those checksums")
    func checksums() {
        let entries = Contract.checksums
        let listed = entries.map { $0.file }
        #expect(!listed.isEmpty)
        #expect(listed == listed.sorted())
        #expect(Contract.files == (listed + [Contract.checksumList]).sorted())
        for entry in entries {
            let hex = SHA256.hash(data: Contract.data(entry.file)).map { String(format: "%02x", $0) }.joined()
            #expect(hex == entry.hex, "\(entry.file) differs from CHECKSUMS.sha256: run scripts/sync-contract.sh")
        }
    }
    #endif

    @Test("X-Attro-SDK is the contract's header, on its iOS platform, with a version the server serves")
    func sdkHeader() throws {
        let header = try #require(Contract.manifest["sdkHeader"])
        #expect(header["name"]?.stringValue == SDKHeader.name)
        #expect(header["format"]?.stringValue == "<platform>/<major>.<minor>.<patch>")
        #expect(header["platforms"]?.arrayValue?.contains(.string(SDKHeader.platform)) == true)

        #expect(SDKHeader.value == "ios/\(Attro.sdkVersion)")
        let regex = try NSRegularExpression(pattern: #"^ios/\d{1,4}\.\d{1,4}\.\d{1,4}$"#)
        let value = SDKHeader.value
        #expect(regex.firstMatch(in: value, options: [], range: NSRange(value.startIndex..<value.endIndex, in: value)) != nil)

        let minimum = try #require(Contract.manifest["minimumSdkVersion"]?["ios"]?.stringValue)
        #expect(
            versionParts(Attro.sdkVersion).lexicographicallyPrecedes(versionParts(minimum)) == false,
            "SDK \(Attro.sdkVersion) is below the contract's iOS minimum \(minimum): the server answers 426"
        )
    }

    @Test("Every path the SDK calls is a canonical iOS endpoint, with the app key and the SDK gate")
    func paths() throws {
        #expect(Set(AttroEngine.Path.all).count == AttroEngine.Path.all.count)
        for path in AttroEngine.Path.all {
            let endpoint = try #require(Contract.endpoint(path), "\(path) is not a canonical path of the contract")
            #expect(endpoint["method"]?.stringValue == "POST", "\(path)")
            #expect(endpoint["auth"]?.stringValue == "x-api-key", "\(path)")
            #expect(endpoint["platforms"]?.arrayValue?.contains(.string("ios")) == true, "\(path)")
            #expect(endpoint["sdkGated"]?.boolValue == true, "\(path)")
        }
    }

    @Test("Every fixture is listed in fixtures.json and matches the schema of its endpoint and status")
    func fixtures() throws {
        let manifest = try JSONDecoder().decode([String: FixtureEntry].self, from: Fixture.data("fixtures"))
        let dir = Bundle.module.url(forResource: "fixtures", withExtension: "json", subdirectory: "Fixtures")!
            .deletingLastPathComponent()
        let onDisk = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasSuffix(".json") && $0 != "fixtures.json" }
            .map { String($0.dropLast(".json".count)) }
        #expect(Set(manifest.keys) == Set(onDisk))

        for name in manifest.keys.sorted() {
            let entry = manifest[name]!
            let schema: JSONValue?
            if entry.request == true {
                schema = Contract.requestSchema(entry.endpoint)
            } else {
                schema = entry.status.flatMap { Contract.responseSchema(entry.endpoint, status: $0) }
            }
            let what = entry.status.map { String($0) } ?? "request"
            let resolved = try #require(schema, "\(name): the contract has no schema for \(entry.endpoint) \(what)")
            let value = try JSONValue.parse(Fixture.data(name))
            let problems = JSONSchema.violations(of: value, against: resolved)
            #expect(problems.isEmpty, "\(name).json: \(problems)")
        }
    }

    @Test("Every request carries X-Attro-SDK and a body its endpoint's request schema accepts", arguments: ContractCall.allCases)
    func requests(_ call: ContractCall) async throws {
        let h = Harness([.fixture(200, call.fixture)], configuration: call.configuration)
        try await call.perform(on: h.engine)

        #expect(h.server.requests.count == 1)
        let request = try #require(h.server.requests.first)
        #expect(request.header(SDKHeader.name) == "ios/\(Attro.sdkVersion)")
        #expect(request.header("x-api-key") != nil)

        let schema = try #require(Contract.requestSchema(request.url.path), "\(request.url.path) has no request schema")
        let body = try JSONValue.parse(request.body)
        let problems = JSONSchema.violations(of: body, against: schema)
        #expect(problems.isEmpty, "\(call.rawValue): \(problems)")
        // The server ignores unknown fields, so a misspelled one would pass
        // unnoticed: every field sent must be one the schema declares.
        let declared = Set(schema["properties"]?.objectValue?.keys.map { $0 } ?? [])
        let sent = Set(body.objectValue?.keys.map { $0 } ?? [])
        #expect(sent.isSubset(of: declared), "\(call.rawValue) sends undeclared fields \(sent.subtracting(declared))")
        if call == .linkWithUserToken {
            #expect(body["appUserToken"]?.stringValue == "user-token-123")
        }
    }

    @Test("426 SDK_UPGRADE_REQUIRED is surfaced once, not retried and not kept for later")
    func upgradeRequired() async throws {
        let h = Harness([.fixture(426, "upgrade-required-426")])
        do {
            _ = try await h.engine.handleUniversalLink(URL(string: "https://get-attro.com/a/demo-app/abc12345")!, appUserId: "u")
            Issue.record("expected an error")
        } catch let error as AttroError {
            guard case .serverError(let status, let message, let retryable) = error else {
                Issue.record("unexpected \(error)")
                return
            }
            #expect(status == 426)
            #expect(!retryable)
            #expect(!error.isRetryable)
            #expect(message?.contains("no longer supported") == true)
        }
        #expect(h.server.requests.count == 1)
        #expect(await h.engine.retryPendingAttributions().isEmpty)
        #expect(h.server.requests.count == 1)
    }
}

@Suite("JSONSchema validator")
struct JSONSchemaTests {
    private func valid(_ value: JSONValue, _ schemaFile: String) -> Bool {
        JSONSchema.violations(of: value, against: Contract.json(schemaFile)).isEmpty
    }

    @Test("Parses strictly: a boolean is never a number")
    func parsing() throws {
        let value = try JSONValue.parse(Data(#"[true, 1, 1.5, null, "1", {"a": false}]"#.utf8))
        #expect(value == .array([.bool(true), .number(1), .number(1.5), .null, .string("1"), .object(["a": .bool(false)])]))
    }

    @Test("oneOf, const, enum, required and additionalProperties are enforced")
    func attributionResponse() {
        let schema = "attribution-response.schema.json"
        #expect(valid(.object(["attributed": .bool(false), "reason": .string("unknown_link")]), schema))
        #expect(!valid(.object(["attributed": .bool(false), "reason": .string("unknown_link"), "extra": .number(1)]), schema))
        #expect(!valid(.object(["attributed": .bool(false), "reason": .string("because")]), schema))
        #expect(!valid(.object(["attributed": .bool(true)]), schema))
        #expect(!valid(.object(["attributed": .string("true"), "reason": .string("unknown_link")]), schema))
    }

    @Test("integer, type lists, items and required are enforced")
    func deviceError() {
        let schema = "device-error.schema.json"
        #expect(valid(.object(["error": .string("x"), "retryAfter": .number(42)]), schema))
        #expect(valid(.object(["error": .string("x"), "currentStatus": .null, "fields": .array([.string("code")])]), schema))
        #expect(!valid(.object(["error": .string("x"), "retryAfter": .number(1.5)]), schema))
        #expect(!valid(.object(["error": .string("x"), "retryAfter": .bool(true)]), schema))
        #expect(!valid(.object(["error": .string("x"), "fields": .array([.number(1)])]), schema))
        #expect(!valid(.object(["retryAfter": .number(1)]), schema))
    }

    @Test("pattern, maxLength and minLength are enforced")
    func strings() {
        #expect(valid(.object(["provider": .string("demo-idp")]), "my-affiliate-request.schema.json"))
        #expect(!valid(.object(["provider": .string("Not A Slug")]), "my-affiliate-request.schema.json"))
        let request: (String) -> JSONValue = { code in
            .object([
                "code": .string(code), "installId": .string("i"), "requestId": .string("r"), "appUserId": .string("u"),
            ])
        }
        #expect(valid(request("X"), "code-attribution-request.schema.json"))
        #expect(!valid(request(""), "code-attribution-request.schema.json"))
        #expect(!valid(request(String(repeating: "c", count: 201)), "code-attribution-request.schema.json"))
    }

    @Test("An unknown keyword or format is a violation, never ignored")
    func unknownKeywords() {
        #expect(!JSONSchema.violations(of: .null, against: .object(["$ref": .string("#/x")])).isEmpty)
        #expect(!JSONSchema.violations(of: .string("x"), against: .object(["format": .string("email")])).isEmpty)
        #expect(JSONSchema.violations(of: .number(1), against: .bool(true)).isEmpty)
        #expect(!JSONSchema.violations(of: .number(1), against: .bool(false)).isEmpty)
    }
}
