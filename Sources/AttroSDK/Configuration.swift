import Foundation

extension Attro {

    /// One Attro project the app belongs to: its app key and the link space
    /// (Universal Links) that opens this app for it.
    ///
    /// An app usually serves one project. An app that serves several programs of
    /// one organization lists each: the SDK calls the device endpoints with the
    /// key of the project whose link was opened (contract §2).
    public struct Project: Sendable, Equatable {
        /// The project's **app key** (`x-api-key`), generated in
        /// **Project → Integrations → App identity**. It is shipped inside the
        /// app and assumed extractable: it authorizes the device endpoints only.
        /// Never put the **server key** in an app.
        public let appKey: String

        /// The project's `public_slug`. Platform-domain links look like
        /// `https://<platform>/a/<public_slug>/<code>`. When nil, the SDK
        /// accepts any slug on the platform domain for this project (the server
        /// still resolves the code in the key's project only).
        public let publicSlug: String?

        /// Custom link domains of this project (host names only, for example
        /// `"go.example.com"`). Links there look like
        /// `https://<custom-domain>/r/<code>`.
        public let customDomains: [String]

        public init(appKey: String, publicSlug: String? = nil, customDomains: [String] = []) {
            self.appKey = appKey
            self.publicSlug = publicSlug?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            self.customDomains = customDomains.map(Attro.Project.normalizeHost)
        }

        static func normalizeHost(_ host: String) -> String {
            var value = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            for scheme in ["https://", "http://"] where value.hasPrefix(scheme) {
                value.removeFirst(scheme.count)
            }
            while value.hasSuffix("/") { value.removeLast() }
            return value
        }
    }

    /// Returns a token from the tenant's backend for `appUserId` (user-token
    /// mode, contract §3). Your backend obtains it from
    /// `POST /api/app/user-token` with the server key; tokens are valid for one
    /// hour. Return nil when the project does not require user tokens.
    public typealias AppUserTokenProvider = @Sendable (_ appUserId: String) async throws -> String?

    /// SDK configuration. `configure` replaces the whole configuration
    /// (last write wins); configure once, at launch.
    public struct Configuration: Sendable {
        /// The main project: its key is used for typed codes, the probabilistic
        /// match and the refer-a-friend endpoints.
        public let project: Project

        /// Further projects of the same organization served by this app.
        public let additionalProjects: [Project]

        /// Base URL of Attro. Its host is also the platform link domain.
        public let baseURL: URL

        /// Whether to call the opt-in probabilistic install match
        /// (`/api/ios/match`). Off by default. Turn it on only when the project
        /// has turned on **Probabilistic install matching** in the Attro admin
        /// and the app shows its users that disclosure (contract §3.3). The
        /// server answers `not_enabled` for a project that has not opted in.
        public let probabilisticMatching: Bool

        /// User-token mode: supplies `appUserToken` for each request.
        public let appUserTokenProvider: AppUserTokenProvider?

        /// The platform host, lower case (for example `get-attro.com`).
        public var platformHost: String? { baseURL.host?.lowercased() }

        /// Every configured project, main project first.
        public var projects: [Project] { [project] + additionalProjects }

        public init(
            project: Project,
            additionalProjects: [Project] = [],
            baseURL: URL = URL(string: "https://get-attro.com")!,
            probabilisticMatching: Bool = false,
            appUserTokenProvider: AppUserTokenProvider? = nil
        ) {
            self.project = project
            self.additionalProjects = additionalProjects
            self.baseURL = baseURL
            self.probabilisticMatching = probabilisticMatching
            self.appUserTokenProvider = appUserTokenProvider
        }

        /// Convenience for an app that serves one project.
        public init(
            appKey: String,
            publicSlug: String? = nil,
            customDomains: [String] = [],
            baseURL: URL = URL(string: "https://get-attro.com")!,
            probabilisticMatching: Bool = false,
            appUserTokenProvider: AppUserTokenProvider? = nil
        ) {
            self.init(
                project: Project(appKey: appKey, publicSlug: publicSlug, customDomains: customDomains),
                baseURL: baseURL,
                probabilisticMatching: probabilisticMatching,
                appUserTokenProvider: appUserTokenProvider
            )
        }

        /// The project a parsed link belongs to, or nil when no configured
        /// project claims it.
        func project(for link: AttroLink) -> Project? {
            switch link.kind {
            case .platform:
                guard let slug = link.publicSlug?.lowercased() else { return nil }
                if let exact = projects.first(where: { $0.publicSlug == slug }) {
                    return exact
                }
                // A project without a configured slug accepts any slug.
                return projects.first(where: { $0.publicSlug == nil })
            case .customDomain:
                return projects.first(where: { $0.customDomains.contains(link.host) })
            }
        }

        /// The project for an explicit public slug (nil means the main project).
        func project(publicSlug: String?) -> Project? {
            guard let slug = publicSlug?.lowercased() else { return project }
            return projects.first(where: { $0.publicSlug == slug })
        }
    }
}
