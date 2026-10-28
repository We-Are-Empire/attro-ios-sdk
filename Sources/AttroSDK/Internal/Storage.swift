import Foundation

/// An attribution attempt that failed transiently and must be retried with
/// the SAME ids, so the server replays it instead of recording a second click
/// or binding (contract §3: "503: retry with the same ids").
struct PendingAttempt: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case link
        case code
    }

    let kind: Kind
    /// The link URL, or the typed code (trimmed).
    let value: String
    /// The project for a typed code (nil = main project). Links re-resolve
    /// their project from the URL.
    let publicSlug: String?
    let requestId: String
    /// The app user at the time of the touch: the row is bound to it for good,
    /// so a later retry still names it.
    let appUserId: String
    let createdAt: Date

    func sameAttempt(as other: PendingAttempt) -> Bool {
        kind == other.kind && value == other.value && publicSlug == other.publicSlug && appUserId == other.appUserId
    }
}

/// Thread-safe persistence for SDK state. UserDefaults only (the install id is
/// in the Keychain, see InstallIdStore). Nothing here is sensitive: the last
/// attribution id, retry bookkeeping and a cached WebKit User-Agent.
actor AttroStorage {
    private let defaults: UserDefaults
    private let prefix = "com.attro.sdk."
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Pending attempts older than this are dropped rather than retried.
    static let pendingMaxAge: TimeInterval = 7 * 24 * 60 * 60
    /// At most this many pending attempts are kept (newest win).
    static let pendingMaxCount = 10

    private enum Keys {
        static let lastAttribution = "v2.lastAttribution"
        static let pendingAttempts = "v2.pendingAttempts"
        static let matchOutcome = "v2.matchOutcome"
        static let webKitUserAgent = "v2.webKitUserAgent"
        static let webKitUserAgentOS = "v2.webKitUserAgentOS"
        /// v1 keys: client-side affiliate/offer/click ids and the old
        /// fingerprint match flags. Removed on configure.
        static let legacy = ["attributionChecked", "storedAttribution", "configuredAt", "pendingCheck"]
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Last attribution

    /// The attribution RevenueCat should point at.
    var lastAttribution: AttributionResult? {
        guard let data = defaults.data(forKey: prefix + Keys.lastAttribution) else { return nil }
        return try? decoder.decode(AttributionResult.self, from: data)
    }

    /// Record an attributed answer. Deterministic first: a probabilistic
    /// result never replaces a deterministic one. Returns whether it became
    /// the current attribution.
    @discardableResult
    func recordAttribution(_ result: AttributionResult) -> Bool {
        if !result.source.isDeterministic, let current = lastAttribution, current.source.isDeterministic {
            return false
        }
        guard let data = try? encoder.encode(result) else { return false }
        defaults.set(data, forKey: prefix + Keys.lastAttribution)
        return true
    }

    // MARK: - Pending attempts

    func pendingAttempts(now: Date = Date()) -> [PendingAttempt] {
        guard let data = defaults.data(forKey: prefix + Keys.pendingAttempts),
              let all = try? decoder.decode([PendingAttempt].self, from: data) else {
            return []
        }
        return all.filter { now.timeIntervalSince($0.createdAt) < Self.pendingMaxAge }
    }

    /// The pending attempt for the same touch, so a retry reuses its ids.
    func pendingAttempt(matching attempt: PendingAttempt) -> PendingAttempt? {
        pendingAttempts().first { $0.sameAttempt(as: attempt) }
    }

    func savePending(_ attempt: PendingAttempt) {
        var all = pendingAttempts().filter { $0.requestId != attempt.requestId }
        all.append(attempt)
        if all.count > Self.pendingMaxCount {
            all.removeFirst(all.count - Self.pendingMaxCount)
        }
        writePending(all)
    }

    func removePending(requestId: String) {
        writePending(pendingAttempts().filter { $0.requestId != requestId })
    }

    private func writePending(_ attempts: [PendingAttempt]) {
        if attempts.isEmpty {
            defaults.removeObject(forKey: prefix + Keys.pendingAttempts)
        } else if let data = try? encoder.encode(attempts) {
            defaults.set(data, forKey: prefix + Keys.pendingAttempts)
        }
    }

    // MARK: - Probabilistic match

    /// The definitive answer of the install's probabilistic match, once known.
    var matchOutcomeRecorded: Bool {
        defaults.object(forKey: prefix + Keys.matchOutcome) != nil
    }

    func setMatchOutcomeRecorded(reason: String) {
        defaults.set(reason, forKey: prefix + Keys.matchOutcome)
    }

    // MARK: - WebKit User-Agent cache

    /// The cached WebKit User-Agent, valid only for the OS version it was read on.
    func webKitUserAgent(osVersion: String) -> String? {
        guard defaults.string(forKey: prefix + Keys.webKitUserAgentOS) == osVersion else { return nil }
        return defaults.string(forKey: prefix + Keys.webKitUserAgent)
    }

    func setWebKitUserAgent(_ userAgent: String, osVersion: String) {
        defaults.set(userAgent, forKey: prefix + Keys.webKitUserAgent)
        defaults.set(osVersion, forKey: prefix + Keys.webKitUserAgentOS)
    }

    // MARK: - Housekeeping

    /// Remove v1 state (client-side affiliate ids of the retired v1 contract).
    func purgeLegacyKeys() {
        for key in Keys.legacy {
            defaults.removeObject(forKey: prefix + key)
        }
    }

    /// Clear all stored data (for testing).
    func reset() {
        for key in [Keys.lastAttribution, Keys.pendingAttempts, Keys.matchOutcome,
                    Keys.webKitUserAgent, Keys.webKitUserAgentOS] + Keys.legacy {
            defaults.removeObject(forKey: prefix + key)
        }
    }
}
