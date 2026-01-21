#if canImport(UIKit)
import UIKit
#endif
import Foundation

/// Device information for fingerprinting
struct DeviceInfo: Encodable, Sendable {
    let screenWidth: Int
    let screenHeight: Int
    let timezone: String
    let language: String

    /// Collect current device information
    @MainActor
    static var current: DeviceInfo {
        #if canImport(UIKit) && !os(watchOS)
        let screen = UIScreen.main.bounds
        let scale = UIScreen.main.scale
        return DeviceInfo(
            screenWidth: Int(screen.width * scale),
            screenHeight: Int(screen.height * scale),
            timezone: TimeZone.current.identifier,
            language: currentLanguage
        )
        #else
        // macOS or other platforms
        return DeviceInfo(
            screenWidth: 0,
            screenHeight: 0,
            timezone: TimeZone.current.identifier,
            language: currentLanguage
        )
        #endif
    }

    private static var currentLanguage: String {
        if #available(iOS 16, macOS 13, *) {
            return Locale.current.language.languageCode?.identifier ?? "en"
        } else {
            return Locale.current.languageCode ?? "en"
        }
    }
}

/// Request body for the match API
struct MatchRequest: Encodable {
    let screenWidth: Int?
    let screenHeight: Int?
    let timezone: String?
    let language: String?

    init(deviceInfo: DeviceInfo) {
        self.screenWidth = deviceInfo.screenWidth > 0 ? deviceInfo.screenWidth : nil
        self.screenHeight = deviceInfo.screenHeight > 0 ? deviceInfo.screenHeight : nil
        self.timezone = deviceInfo.timezone
        self.language = deviceInfo.language
    }
}

/// Request body for the my-affiliate API
struct MyAffiliateRequest: Encodable {
    let rideUserId: String
    let orgSlug: String?
}
