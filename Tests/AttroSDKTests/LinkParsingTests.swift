import Testing
import Foundation
@testable import AttroSDK

/// Universal Link format and `/r/{code}` parsing (contract §2), mirroring the
/// server's `parseAppLinkPath`.
@Suite("Universal Link parsing")
struct LinkParsingTests {
    let config = Harness.configuration()

    private func parse(_ string: String) -> AttroLink? {
        AttroLink(url: URL(string: string)!, configuration: config)
    }

    @Test("Platform link /a/<public_slug>/<code> parses, with the query kept for sub-IDs")
    func platformLink() throws {
        let link = try #require(parse("https://get-attro.com/a/demo-app/abc12345?sub1=story"))
        #expect(link.kind == .platform)
        #expect(link.publicSlug == "demo-app")
        #expect(link.code == "abc12345")
        #expect(link.host == "get-attro.com")
        #expect(link.url.absoluteString == "https://get-attro.com/a/demo-app/abc12345?sub1=story")
        #expect(config.project(for: link)?.appKey == "app_key_main")
    }

    @Test("Custom-domain link /r/<code> parses and belongs to the domain's project")
    func customDomainLink() throws {
        let link = try #require(parse("https://go.example.com/r/Code_9-x"))
        #expect(link.kind == .customDomain)
        #expect(link.publicSlug == nil)
        #expect(link.code == "Code_9-x")
        #expect(config.project(for: link)?.appKey == "app_key_main")
    }

    @Test("Platform /r/<code> is not a Universal Link: no app claims it")
    func platformRIsNotALink() {
        #expect(parse("https://get-attro.com/r/abc12345") == nil)
    }

    @Test("/a/ on a custom domain is not a link: the custom domain claims /r/* only")
    func appPathOnCustomDomain() {
        #expect(parse("https://go.example.com/a/demo-app/abc12345") == nil)
    }

    @Test("A slug of another configured project routes to that project's key")
    func additionalProject() throws {
        let link = try #require(parse("https://get-attro.com/a/second-program/xyz"))
        #expect(config.project(for: link)?.appKey == "app_key_second")
    }

    @Test("A slug no configured project has is not this app's link")
    func foreignSlug() throws {
        let link = try #require(parse("https://get-attro.com/a/other-tenant/abc12345"))
        #expect(config.project(for: link) == nil)
        #expect(Attro.Configuration(appKey: "k", publicSlug: "demo-app").project(for: link) == nil)
    }

    @Test("A project without a configured slug accepts any platform slug")
    func slugless() throws {
        let slugless = Attro.Configuration(appKey: "k")
        let link = try #require(AttroLink(url: URL(string: "https://get-attro.com/a/anything/abc")!, configuration: slugless))
        #expect(slugless.project(for: link)?.appKey == "k")
    }

    @Test("Hosts outside the platform and custom domains are refused", arguments: [
        "https://evil.example/a/demo-app/abc12345",
        "https://get-attro.com.evil.example/a/demo-app/abc12345",
        "https://evil.example/r/abc12345",
    ])
    func foreignHost(_ url: String) {
        #expect(parse(url) == nil)
    }

    @Test("Shapes the server's parser refuses are refused", arguments: [
        "https://get-attro.com/join/abc12345",            // not a tenant link shape (contract test)
        "https://get-attro.com/a/demo-app",               // no code
        "https://get-attro.com/a/demo-app/abc/extra",     // extra segment
        "https://get-attro.com/a/demo-app/abc.def",       // '.' outside [A-Za-z0-9_-]
        "https://get-attro.com/a/demo-app/%25",           // wildcard-like '%'
        "https://get-attro.com/a/demo-app/a%2Fb",         // encoded slash decodes to '/'
        "https://go.example.com/r/abc/extra",
        "https://go.example.com/r/",
        "https://get-attro.com/app/track?click=1",        // v1 deferred page, not a link
        "ftp://get-attro.com/a/demo-app/abc12345",
        "http://go.example.com/r/abc12345",               // custom domains are https only
    ])
    func refusedShapes(_ url: String) {
        #expect(parse(url) == nil)
    }

    @Test("Segments are limited to 100 characters")
    func segmentLength() {
        let ok = String(repeating: "a", count: 100)
        let tooLong = String(repeating: "a", count: 101)
        #expect(parse("https://get-attro.com/a/demo-app/\(ok)") != nil)
        #expect(parse("https://get-attro.com/a/demo-app/\(tooLong)") == nil)
    }

    @Test("Empty path segments are dropped and segments percent-decoded, like the server")
    func normalisation() throws {
        let link = try #require(parse("https://get-attro.com//a//demo-app/%61bc/"))
        #expect(link.code == "abc")
        #expect(link.publicSlug == "demo-app")
    }

    @Test("Hosts compare case-insensitively; configured domains are normalised")
    func hostCase() throws {
        #expect(parse("https://GET-ATTRO.com/a/demo-app/abc") != nil)
        let config = Attro.Configuration(appKey: "k", customDomains: [" https://Go.Example.com/ "])
        #expect(config.project.customDomains == ["go.example.com"])
        #expect(AttroLink(url: URL(string: "https://go.example.com/r/abc")!, configuration: config) != nil)
    }

    @Test("Platform links follow a development base URL's host and scheme")
    func developmentBaseURL() {
        let dev = Attro.Configuration(appKey: "k", publicSlug: "demo-app", baseURL: URL(string: "http://localhost:3000")!)
        #expect(AttroLink(url: URL(string: "http://localhost:3000/a/demo-app/abc")!, configuration: dev) != nil)
        #expect(AttroLink(url: URL(string: "https://get-attro.com/a/demo-app/abc")!, configuration: dev) == nil)
    }
}
