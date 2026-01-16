# RideDeskSDK

A lightweight Swift Package for integrating RideDesk affiliate tracking into iOS apps.

## Features

- **Deferred Attribution** - Automatically match users to affiliate clicks on first app launch
- **Universal Link Handling** - Parse attribution from Universal Links
- **RevenueCat Integration** - Optional integration to set subscriber attributes
- **Refer-a-Friend** - Get referral links and stats for logged-in users

## Requirements

- iOS 15.0+ / macOS 12.0+
- Swift 5.9+

## Installation

### Swift Package Manager

Add RideDeskSDK to your project via Xcode:

1. File → Add Package Dependencies
2. Enter the repository URL: `https://github.com/We-Are-Empire/ridedesk-ios-sdk`
3. Select version and add to your target

Or add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/We-Are-Empire/ridedesk-ios-sdk", from: "1.0.0")
]
```

## Quick Start

### 1. Configure the SDK

Configure RideDesk on app launch:

```swift
import RideDeskSDK

@main
struct MyApp: App {
    init() {
        RideDesk.configure(organizationSlug: "ride-ios")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

### 2. Check Deferred Attribution

Check for attribution on first app launch:

```swift
Task {
    if let attribution = try await RideDesk.checkAttribution() {
        print("Attributed to affiliate: \(attribution.affiliateId)")

        // If using RevenueCat, set attributes
        RideDesk.applyToRevenueCat(attribution)
    }
}
```

### 3. Handle Universal Links

Parse attribution from Universal Links:

```swift
.onOpenURL { url in
    if let attribution = RideDesk.parseUniversalLink(url) {
        RideDesk.storeAttribution(attribution)
        RideDesk.applyToRevenueCat(attribution)
    }
}
```

### 4. Refer-a-Friend

Get a user's referral link and stats:

```swift
let referral = try await RideDesk.getMyReferral(userId: currentUser.id)

// Display stats
print("Clicks: \(referral.stats.clicks)")
print("Conversions: \(referral.stats.conversions.approved)")
print("Tokens: \(referral.stats.tokens.balance)")

// Share referral link
let url = referral.trackingLink.url
```

## Complete Integration Example

```swift
import SwiftUI
import RideDeskSDK

@main
struct RideApp: App {
    init() {
        RideDesk.configure(organizationSlug: "ride-ios")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    handleUniversalLink(url)
                }
                .task {
                    await checkAttribution()
                }
        }
    }

    private func handleUniversalLink(_ url: URL) {
        if let attribution = RideDesk.parseUniversalLink(url) {
            RideDesk.storeAttribution(attribution)
            RideDesk.applyToRevenueCat(attribution)
        }
    }

    private func checkAttribution() async {
        do {
            if let attribution = try await RideDesk.checkAttribution() {
                RideDesk.applyToRevenueCat(attribution)
            }
        } catch {
            print("Attribution check failed: \(error)")
        }
    }
}

// Refer-a-Friend View
struct ReferralView: View {
    @State private var referral: ReferralInfo?
    let userId: String

    var body: some View {
        VStack(spacing: 16) {
            if let referral {
                Text("Your Referral Link")
                    .font(.headline)

                Text(referral.trackingLink.url)
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 24) {
                    StatView(value: referral.stats.clicks, label: "Clicks")
                    StatView(value: referral.stats.conversions.approved, label: "Referrals")
                    StatView(value: referral.stats.tokens.balance, label: "Tokens")
                }

                ShareLink(
                    item: URL(string: referral.shareContent.url)!,
                    message: Text(referral.shareContent.text)
                ) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
            } else {
                ProgressView()
            }
        }
        .task {
            referral = try? await RideDesk.getMyReferral(userId: userId)
        }
    }
}

struct StatView: View {
    let value: Int
    let label: String

    var body: some View {
        VStack {
            Text("\(value)")
                .font(.title2.bold())
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
```

## RevenueCat Integration

If you're using RevenueCat, RideDeskSDK can automatically set subscriber attributes:

```swift
import RideDeskSDK
import RevenueCat

// After getting attribution
if let attribution = try await RideDesk.checkAttribution() {
    RideDesk.applyToRevenueCat(attribution)
}
```

This sets the following subscriber attributes:
- `$rd_click_id`
- `$rd_affiliate_id`
- `$rd_offer_id`
- `$rd_org_id`
- `$rd_tracking_code`
- `$rd_attributed_at`

## Universal Links Setup

To receive Universal Links, configure your app:

1. **Add Associated Domains** in your app's entitlements:
   ```
   applinks:ridedesk.vercel.app
   ```

2. **Handle incoming URLs** using SwiftUI's `onOpenURL` or UIKit's scene delegate

## API Reference

### Configuration

```swift
// Basic configuration
RideDesk.configure(organizationSlug: "your-org")

// With custom base URL (for staging)
RideDesk.configure(
    organizationSlug: "your-org",
    baseURL: URL(string: "https://staging.ridedesk.app")!
)

// Full configuration
RideDesk.configure(Configuration(
    organizationSlug: "your-org",
    baseURL: URL(string: "https://ridedesk.vercel.app")!,
    allowedHosts: ["custom.domain.com"]
))
```

### Attribution

```swift
// Check deferred attribution (call once on first launch)
let attribution = try await RideDesk.checkAttribution()

// Parse Universal Link
let attribution = RideDesk.parseUniversalLink(url)

// Check if URL is a RideDesk link
let isRideDeskLink = RideDesk.isRideDeskLink(url)

// Store attribution for later use
RideDesk.storeAttribution(attribution)

// Get stored attribution
let stored = await RideDesk.getStoredAttribution()
```

### Referrals

```swift
// Get referral info for a user
let referral = try await RideDesk.getMyReferral(userId: "user-uuid")

// Access referral data
referral.trackingLink.url      // Shareable URL
referral.stats.clicks          // Click count
referral.stats.conversions     // Conversion breakdown
referral.stats.tokens          // Token balance
referral.shareContent          // Pre-formatted share content
```

### RevenueCat (if available)

```swift
// Apply attribution to RevenueCat
RideDesk.applyToRevenueCat(attribution)
```

## Error Handling

```swift
do {
    let referral = try await RideDesk.getMyReferral(userId: userId)
} catch RideDeskError.notConfigured {
    print("Call RideDesk.configure() first")
} catch RideDeskError.serverError(let code, let message) {
    print("Server error \(code): \(message ?? "Unknown")")
} catch RideDeskError.networkError(let error) {
    print("Network error: \(error)")
}
```

## Testing

For testing, you can reset the SDK state:

```swift
await RideDesk.reset()
```

## License

MIT License - see LICENSE file for details.

## Support

For issues and feature requests, please open an issue on GitHub.
