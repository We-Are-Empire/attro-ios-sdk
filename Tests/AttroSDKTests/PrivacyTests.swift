import Testing
import Foundation
@testable import AttroSDK

/// The privacy manifest matches what the SDK collects, and the SDK uses no
/// fingerprinting APIs (07-F-02 / 07-F-05).
@Suite("Privacy")
struct PrivacyTests {
    /// The package root, from this file's path.
    private static var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private static func manifest(_ target: String) throws -> [String: Any] {
        let url = root.appendingPathComponent("Sources/\(target)/Resources/PrivacyInfo.xcprivacy")
        let data = try Data(contentsOf: url)
        return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    private static func sources() throws -> [(String, String)] {
        let dir = root.appendingPathComponent("Sources")
        let files = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
        return try files.map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) }
    }

    @Test("AttroSDK manifest: no tracking; declares exactly the data it sends")
    func sdkManifest() throws {
        let manifest = try Self.manifest("AttroSDK")
        #expect(manifest["NSPrivacyTracking"] as? Bool == false)
        #expect((manifest["NSPrivacyTrackingDomains"] as? [String])?.isEmpty == true)

        let collected = try #require(manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        let types = Set(collected.compactMap { $0["NSPrivacyCollectedDataType"] as? String })
        #expect(types == [
            "NSPrivacyCollectedDataTypeDeviceID",           // the Keychain install id
            "NSPrivacyCollectedDataTypeUserID",             // the RevenueCat app user id
            "NSPrivacyCollectedDataTypeProductInteraction", // link opened / code typed
        ])
        for entry in collected {
            #expect(entry["NSPrivacyCollectedDataTypeTracking"] as? Bool == false)
            #expect(entry["NSPrivacyCollectedDataTypeLinked"] as? Bool == true)
            #expect((entry["NSPrivacyCollectedDataTypePurposes"] as? [String])?.isEmpty == false)
        }

        let apis = try #require(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        #expect(apis.count == 1)
        #expect(apis.first?["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults")
        #expect(apis.first?["NSPrivacyAccessedAPITypeReasons"] as? [String] == ["CA92.1"])
    }

    @Test("AttroRevenueCat manifest: collects nothing itself")
    func revenueCatManifest() throws {
        let manifest = try Self.manifest("AttroRevenueCat")
        #expect(manifest["NSPrivacyTracking"] as? Bool == false)
        #expect((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty == true)
        #expect((manifest["NSPrivacyAccessedAPITypes"] as? [Any])?.isEmpty == true)
    }

    @Test("No fingerprinting or undeclared required-reason APIs in the sources")
    func noFingerprinting() throws {
        let forbidden = [
            "UIScreen", "TimeZone.current", "Locale.current", "preferredLanguages",
            "identifierForVendor", "advertisingIdentifier", "ASIdentifierManager", "AdSupport",
            "systemUptime", "mach_absolute_time", "kern.boottime", "volumeAvailableCapacity",
            "systemFreeSize", "activeInputModes", "creationDate", "modificationDate",
            "UIDevice.current.name", "hw.machine", "utsname",
        ]
        for (file, text) in try Self.sources() {
            for token in forbidden {
                #expect(!text.contains(token), "\(file) uses \(token)")
            }
        }
    }

    @Test("No v1 `$rd_*` attribute or client-described affiliate fields remain")
    func noLegacyContract() throws {
        for (file, text) in try Self.sources() {
            #expect(!text.contains("$rd_"), "\(file) still names a $rd_ attribute")
            #expect(!text.contains("screenWidth"), "\(file) still collects screen size")
        }
    }
}
