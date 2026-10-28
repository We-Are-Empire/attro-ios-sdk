import Foundation
#if canImport(WebKit)
import WebKit
#endif

/// User-Agent strings the SDK sends.
enum UserAgent {
    /// The SDK's truthful User-Agent, for every endpoint except the
    /// probabilistic match: `AttroSDK/2.0.0 (<bundle id>; iOS 17_5)`.
    static var sdk: String {
        let bundle = Bundle.main.bundleIdentifier ?? "unknown-bundle"
        return "AttroSDK/\(Attro.sdkVersion) (\(bundle); \(osName) \(osVersion))"
    }

    /// The running OS version, underscore-separated like Apple's
    /// User-Agents (`17_5`, `17_4_1`).
    static var osVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        if v.patchVersion > 0 {
            return "\(v.majorVersion)_\(v.minorVersion)_\(v.patchVersion)"
        }
        return "\(v.majorVersion)_\(v.minorVersion)"
    }

    private static var osName: String {
        #if os(iOS)
        return "iOS"
        #elseif os(macOS)
        return "macOS"
        #else
        return "OS"
        #endif
    }
}

/// Supplies the app's WebKit User-Agent for the opt-in probabilistic match
/// (contract §3.3: "send the app's WebKit User-Agent, not the default
/// CFNetwork one"). Only called when probabilistic matching is on.
protocol WebKitUserAgentProviding: Sendable {
    @MainActor func webKitUserAgent() async -> String?
}

/// Reads `navigator.userAgent` from a throwaway `WKWebView`, as the contract
/// prescribes. The SDK caches the answer per OS version, so this runs at most
/// once per OS update.
struct WKWebViewUserAgentProvider: WebKitUserAgentProviding {
    @MainActor
    func webKitUserAgent() async -> String? {
        #if canImport(WebKit)
        let webView = WKWebView(frame: .zero)
        return await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            webView.evaluateJavaScript("navigator.userAgent") { value, _ in
                // Keep the web view alive until the script answered.
                _ = webView
                continuation.resume(returning: value as? String)
            }
        }
        #else
        return nil
        #endif
    }
}
