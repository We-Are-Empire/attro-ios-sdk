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

    /// The real device User-Agent to send on the match request.
    ///
    /// P2-03: the SDK used to send a static `AttroSDK/1.0` User-Agent, which the
    /// backend matcher cannot relate to the Safari/WebKit User-Agent captured in
    /// the click-time device snapshot — collapsing every match to IP-only. We now
    /// send a Safari-on-iOS-shaped User-Agent built from the real OS version so
    /// the backend can award the User-Agent (browser-family) confidence points.
    let userAgent: String

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
            language: currentLanguage,
            userAgent: currentUserAgent
        )
        #else
        // macOS or other platforms
        return DeviceInfo(
            screenWidth: 0,
            screenHeight: 0,
            timezone: TimeZone.current.identifier,
            language: currentLanguage,
            userAgent: currentUserAgent
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

    /// Build a real device User-Agent string.
    ///
    /// We deliberately shape it like mobile Safari/WebKit (the browser that
    /// captured the click-time snapshot) so the backend matcher recognises the
    /// "Safari" browser family and awards User-Agent confidence points instead of
    /// degrading to an IP-only match. The OS version is read from the running
    /// device; on non-iOS platforms we still emit a Safari-shaped fallback.
    static var currentUserAgent: String {
        let osVersion = systemVersionForUserAgent
        // Mirrors the structure of mobile Safari's User-Agent. The WebKit/Safari
        // tokens are what the backend keys on for browser-family matching.
        return "Mozilla/5.0 (iPhone; CPU iPhone OS \(osVersion) like Mac OS X) "
            + "AppleWebKit/605.1.15 (KHTML, like Gecko) "
            + "Mobile/15E148 Safari/604.1 AttroSDK/1.0"
    }

    /// The default User-Agent used when a caller does not supply one. Computed
    /// off the main actor (it only reads ProcessInfo), so it is safe as a
    /// default argument on the API client.
    static var defaultUserAgent: String { currentUserAgent }

    /// The OS version formatted for a User-Agent (underscore-separated, e.g.
    /// "17_4_1"), matching Apple's User-Agent convention.
    private static var systemVersionForUserAgent: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        if v.patchVersion > 0 {
            return "\(v.majorVersion)_\(v.minorVersion)_\(v.patchVersion)"
        }
        return "\(v.majorVersion)_\(v.minorVersion)"
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
