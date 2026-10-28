import Foundation

/// A tenant Universal Link (contract §2).
///
/// - On the platform domain: `https://<platform>/a/<public_slug>/<code>`.
/// - On a project's custom domain: `https://<custom-domain>/r/<code>`.
///
/// `https://<platform>/r/<code>` is **not** a Universal Link: no app claims it,
/// it always reaches the server in a browser. The SDK therefore does not treat
/// it as one.
///
/// Parsing mirrors the server (`parseAppLinkPath`): the path is split on `/`,
/// empty segments are dropped, each segment is percent-decoded, and each must
/// match `[A-Za-z0-9_-]{1,100}`. The slug is advisory: the server resolves the
/// code in the app key's project only, so a foreign code never attributes.
public struct AttroLink: Sendable, Hashable {
    /// Where the link lives.
    public enum Kind: Sendable, Hashable {
        /// `https://<platform>/a/<public_slug>/<code>`
        case platform
        /// `https://<custom-domain>/r/<code>`
        case customDomain
    }

    /// The full URL the app received. It is sent to the server unchanged: the
    /// server takes sub-IDs (`sub1`...) from its query.
    public let url: URL

    /// The link's host, lower case.
    public let host: String

    /// Platform or custom-domain link.
    public let kind: Kind

    /// The project's `public_slug` (platform links only).
    public let publicSlug: String?

    /// The tracking link code.
    public let code: String

    /// Parse `url` against the configured platform host and custom domains.
    /// Nil when `url` is not an Attro Universal Link for this app.
    public init?(url: URL, configuration: Attro.Configuration) {
        guard let parsed = AttroLink.parsePath(of: url),
              let host = url.host?.lowercased() else {
            return nil
        }
        let scheme = url.scheme?.lowercased()
        let platformScheme = configuration.baseURL.scheme?.lowercased()
        switch parsed {
        case .platform(let slug, let code):
            // Platform links: the platform host, over the platform's scheme
            // (https in production).
            guard host == configuration.platformHost,
                  scheme == "https" || scheme == platformScheme else { return nil }
            self.init(url: url, host: host, kind: .platform, publicSlug: slug, code: code)
        case .customDomain(let code):
            // Custom domains claim `/r/*`; the platform's `/r/` is never a
            // Universal Link.
            guard scheme == "https",
                  host != configuration.platformHost,
                  configuration.projects.contains(where: { $0.customDomains.contains(host) }) else {
                return nil
            }
            self.init(url: url, host: host, kind: .customDomain, publicSlug: nil, code: code)
        }
    }

    init(url: URL, host: String, kind: Kind, publicSlug: String?, code: String) {
        self.url = url
        self.host = host
        self.kind = kind
        self.publicSlug = publicSlug
        self.code = code
    }

    // MARK: - Path parsing (mirrors the server's parseAppLinkPath)

    enum ParsedPath: Equatable {
        case platform(publicSlug: String, code: String)
        case customDomain(code: String)
    }

    /// The link shape of `url`'s path, independent of its host.
    static func parsePath(of url: URL) -> ParsedPath? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let parts = components.percentEncodedPath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? "" }
        if parts.count == 3, parts[0] == "a", isSegment(parts[1]), isSegment(parts[2]) {
            return .platform(publicSlug: parts[1], code: parts[2])
        }
        if parts.count == 2, parts[0] == "r", isSegment(parts[1]) {
            return .customDomain(code: parts[1])
        }
        return nil
    }

    /// `^[A-Za-z0-9_-]{1,100}$`
    static func isSegment(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 100 else { return false }
        return value.utf8.allSatisfy { byte in
            (byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z"))
                || (byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z"))
                || (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9"))
                || byte == UInt8(ascii: "-")
                || byte == UInt8(ascii: "_")
        }
    }
}
