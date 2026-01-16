import Foundation

/// Thread-safe storage for RideDesk data
actor RideDeskStorage {
    private let defaults: UserDefaults
    private let prefix = "com.ridedesk.sdk."

    private enum Keys {
        static let attributionChecked = "attributionChecked"
        static let storedAttribution = "storedAttribution"
        static let configuredAt = "configuredAt"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Attribution Checked Flag

    /// Whether attribution has already been checked for this install
    var attributionChecked: Bool {
        get { defaults.bool(forKey: prefix + Keys.attributionChecked) }
    }

    func setAttributionChecked(_ value: Bool) {
        defaults.set(value, forKey: prefix + Keys.attributionChecked)
    }

    // MARK: - Stored Attribution

    /// Previously stored attribution data
    var storedAttribution: Attribution? {
        get {
            guard let data = defaults.data(forKey: prefix + Keys.storedAttribution) else {
                return nil
            }
            return try? JSONDecoder().decode(Attribution.self, from: data)
        }
    }

    func setStoredAttribution(_ attribution: Attribution?) {
        if let attribution = attribution {
            let data = try? JSONEncoder().encode(attribution)
            defaults.set(data, forKey: prefix + Keys.storedAttribution)
        } else {
            defaults.removeObject(forKey: prefix + Keys.storedAttribution)
        }
    }

    // MARK: - Configuration

    /// When the SDK was last configured
    var configuredAt: Date? {
        get { defaults.object(forKey: prefix + Keys.configuredAt) as? Date }
    }

    func setConfiguredAt(_ date: Date) {
        defaults.set(date, forKey: prefix + Keys.configuredAt)
    }

    // MARK: - Reset

    /// Clear all stored data (for testing)
    func reset() {
        defaults.removeObject(forKey: prefix + Keys.attributionChecked)
        defaults.removeObject(forKey: prefix + Keys.storedAttribution)
        defaults.removeObject(forKey: prefix + Keys.configuredAt)
    }
}
