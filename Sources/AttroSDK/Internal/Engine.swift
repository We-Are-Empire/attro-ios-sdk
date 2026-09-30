import Foundation

/// The SDK's behaviour, behind the `Attro` facade. Holds no global state, so
/// tests build one with a stub HTTP session and scratch storage.
actor AttroEngine {
    let configuration: Attro.Configuration
    private let client: APIClient
    private let storage: AttroStorage
    private let installIds: InstallIdStore
    private let webKitUserAgent: WebKitUserAgentProviding
    private let now: @Sendable () -> Date

    enum Path {
        static let link = "/api/ios/attribution/link"
        static let code = "/api/ios/attribution/code"
        static let match = "/api/ios/match"
        static let myAffiliate = "/api/ios/my-affiliate"
        static let referralMe = "/api/ios/referral/me"
    }

    init(
        configuration: Attro.Configuration,
        client: APIClient,
        storage: AttroStorage,
        installIds: InstallIdStore,
        webKitUserAgent: WebKitUserAgentProviding,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.configuration = configuration
        self.client = client
        self.storage = storage
        self.installIds = installIds
        self.webKitUserAgent = webKitUserAgent
        self.now = now
    }

    // MARK: - Deterministic attribution

    /// The app was opened by `url` (contract §3.1). Nil when `url` is not an
    /// Attro Universal Link of this app (no request is made).
    func handleUniversalLink(_ url: URL, appUserId: String) async throws -> AttributionOutcome? {
        guard let link = AttroLink(url: url, configuration: configuration),
              configuration.project(for: link) != nil else {
            return nil
        }
        let urlString = url.absoluteString
        guard urlString.utf8.count <= WireLimits.url else {
            throw AttroError.invalidParameter("url (longer than \(WireLimits.url) characters)")
        }
        let attempt = try await attempt(kind: .link, value: urlString, publicSlug: nil, appUserId: appUserId)
        return try await send(attempt)
    }

    /// The user typed an affiliate code (contract §3.2).
    func submitCode(_ code: String, appUserId: String, publicSlug: String?) async throws -> AttributionOutcome {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AttroError.missingParameter("code") }
        guard trimmed.count <= WireLimits.code else {
            throw AttroError.invalidParameter("code (longer than \(WireLimits.code) characters)")
        }
        guard configuration.project(publicSlug: publicSlug) != nil else {
            throw AttroError.invalidParameter("publicSlug (no configured project has it)")
        }
        let attempt = try await attempt(kind: .code, value: trimmed, publicSlug: publicSlug, appUserId: appUserId)
        guard let outcome = try await send(attempt) else {
            throw AttroError.invalidParameter("publicSlug (no configured project has it)")
        }
        return outcome
    }

    /// Retry every attempt that failed transiently, with its original ids.
    func retryPendingAttributions() async -> [AttributionOutcome] {
        var outcomes: [AttributionOutcome] = []
        for attempt in await storage.pendingAttempts(now: now()) {
            do {
                if let outcome = try await send(attempt) { outcomes.append(outcome) }
            } catch {
                AttroLog.info("Pending attribution not delivered yet: \(error.localizedDescription)")
            }
        }
        return outcomes
    }

    // MARK: - Probabilistic match (opt-in)

    /// The opt-in probabilistic install match (contract §3.3). Nil without a
    /// request when matching is off, when the install already has a
    /// deterministic attribution, or once a definitive answer was recorded.
    func matchInstall(appUserId: String) async throws -> AttributionOutcome? {
        guard configuration.probabilisticMatching else { return nil }
        if await storage.matchOutcomeRecorded { return nil }
        if let current = await storage.lastAttribution, current.source.isDeterministic {
            // Deterministic first: an exact attribution already exists.
            return nil
        }
        let appUserId = try validateAppUserId(appUserId)
        let body = MatchRequest(
            installId: installIds.installId(),
            appUserId: appUserId,
            appUserToken: try await appUserToken(for: appUserId)
        )
        let response: AttributionResponse = try await client.post(
            Path.match,
            body: body,
            apiKey: configuration.project.appKey,
            userAgent: await matchUserAgent()
        )
        let outcome = try decode(response)
        switch outcome {
        case .attributed(let result):
            await storage.recordAttribution(result)
            await storage.setMatchOutcomeRecorded(reason: "attributed")
        case .notAttributed(let reason):
            await storage.setMatchOutcomeRecorded(reason: reason.rawValue)
        }
        return outcome
    }

    // MARK: - Refer-a-friend

    func getMyAffiliate(accessToken: String, provider: String) async throws -> AffiliateInfo {
        try await client.post(
            Path.myAffiliate,
            body: ProviderRequest(provider: try validateProvider(provider)),
            apiKey: configuration.project.appKey,
            userAgent: UserAgent.sdk,
            bearerToken: try validateToken(accessToken)
        )
    }

    func getReferralProgram(accessToken: String, provider: String) async throws -> ReferralProgramInfo {
        try await client.post(
            Path.referralMe,
            body: ProviderRequest(provider: try validateProvider(provider)),
            apiKey: configuration.project.appKey,
            userAgent: UserAgent.sdk,
            bearerToken: try validateToken(accessToken)
        )
    }

    // MARK: - State

    func currentAttribution() async -> AttributionResult? {
        await storage.lastAttribution
    }

    var installId: String { installIds.installId() }

    // MARK: - Internals

    private func attempt(
        kind: PendingAttempt.Kind,
        value: String,
        publicSlug: String?,
        appUserId: String
    ) async throws -> PendingAttempt {
        let fresh = PendingAttempt(
            kind: kind,
            value: value,
            publicSlug: publicSlug?.lowercased(),
            requestId: UUID().uuidString.lowercased(),
            appUserId: try validateAppUserId(appUserId),
            createdAt: now()
        )
        // A retry of a touch that failed transiently reuses its request id, so
        // the server replays instead of recording a second click.
        return await storage.pendingAttempt(matching: fresh) ?? fresh
    }

    /// Send one attempt. Nil when its project is no longer configured (the
    /// attempt is dropped). A retryable failure keeps it pending.
    private func send(_ attempt: PendingAttempt) async throws -> AttributionOutcome? {
        let project: Attro.Project?
        switch attempt.kind {
        case .link:
            project = URL(string: attempt.value)
                .flatMap { AttroLink(url: $0, configuration: configuration) }
                .flatMap { configuration.project(for: $0) }
        case .code:
            project = configuration.project(publicSlug: attempt.publicSlug)
        }
        guard let project else {
            await storage.removePending(requestId: attempt.requestId)
            return nil
        }

        do {
            let token = try await appUserToken(for: attempt.appUserId)
            let installId = installIds.installId()
            let response: AttributionResponse
            switch attempt.kind {
            case .link:
                response = try await client.post(
                    Path.link,
                    body: LinkAttributionRequest(
                        url: attempt.value, installId: installId, requestId: attempt.requestId,
                        appUserId: attempt.appUserId, appUserToken: token
                    ),
                    apiKey: project.appKey,
                    userAgent: UserAgent.sdk
                )
            case .code:
                response = try await client.post(
                    Path.code,
                    body: CodeAttributionRequest(
                        code: attempt.value, installId: installId, requestId: attempt.requestId,
                        appUserId: attempt.appUserId, appUserToken: token
                    ),
                    apiKey: project.appKey,
                    userAgent: UserAgent.sdk
                )
            }
            let outcome = try decode(response)
            await storage.removePending(requestId: attempt.requestId)
            if case .attributed(let result) = outcome {
                await storage.recordAttribution(result)
            }
            return outcome
        } catch let error as AttroError where error.isRetryable {
            await storage.savePending(attempt)
            throw error
        } catch {
            await storage.removePending(requestId: attempt.requestId)
            throw error
        }
    }

    private func decode(_ response: AttributionResponse) throws -> AttributionOutcome {
        do {
            return try response.outcome(receivedAt: now())
        } catch {
            throw AttroError.decodingError(error)
        }
    }

    private func appUserToken(for appUserId: String) async throws -> String? {
        guard let provider = configuration.appUserTokenProvider else { return nil }
        let token: String?
        do {
            token = try await provider(appUserId)
        } catch {
            throw AttroError.appUserTokenUnavailable(error)
        }
        guard let token = token?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else {
            return nil
        }
        guard token.count <= WireLimits.appUserToken else {
            throw AttroError.invalidParameter("appUserToken (longer than \(WireLimits.appUserToken) characters)")
        }
        return token
    }

    /// The WebKit User-Agent, cached per OS version; the SDK's own User-Agent
    /// when WebKit cannot supply one (the match then scores on the IP alone,
    /// which never reaches the default threshold).
    private func matchUserAgent() async -> String {
        let os = UserAgent.osVersion
        if let cached = await storage.webKitUserAgent(osVersion: os) { return cached }
        if let fresh = await webKitUserAgent.webKitUserAgent(), !fresh.isEmpty {
            await storage.setWebKitUserAgent(fresh, osVersion: os)
            return fresh
        }
        AttroLog.error("WebKit User-Agent unavailable; the probabilistic match can only use the IP.")
        return UserAgent.sdk
    }

    private func validateAppUserId(_ appUserId: String) throws -> String {
        let trimmed = appUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AttroError.missingParameter("appUserId") }
        guard trimmed.count <= WireLimits.appUserId else {
            throw AttroError.invalidParameter("appUserId (longer than \(WireLimits.appUserId) characters)")
        }
        return trimmed
    }

    private func validateToken(_ accessToken: String) throws -> String {
        let token = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw AttroError.missingParameter("accessToken") }
        return token
    }

    private func validateProvider(_ provider: String) throws -> String {
        let slug = provider.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !slug.isEmpty else { throw AttroError.missingParameter("provider") }
        return slug
    }
}
