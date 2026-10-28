import Foundation

/// The header that identifies the SDK to Attro (contract §8):
/// `X-Attro-SDK: ios/<major>.<minor>.<patch>`, on every request.
///
/// The server refuses a version below its supported minimum with `426`
/// `SDK_UPGRADE_REQUIRED` and counts the versions each project sees, so an
/// old SDK can be retired once no app still ships it.
enum SDKHeader {
    static let name = "X-Attro-SDK"

    /// The platform segment: always `ios`, the platform the SDK ships on
    /// (also on macOS, where only its tests run).
    static let platform = "ios"

    /// `ios/2.0.0`.
    static var value: String { "\(platform)/\(Attro.sdkVersion)" }
}
