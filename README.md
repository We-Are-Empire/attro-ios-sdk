# AttroSDK

A lightweight Swift Package for integrating Attro affiliate tracking into iOS apps.

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

Add AttroSDK to your project via Xcode:

1. File → Add Package Dependencies
2. Enter the repository URL: `https://github.com/We-Are-Empire/attro-ios-sdk`
3. Select version and add to your target

Or add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/We-Are-Empire/attro-ios-sdk", from: "1.0.0")
]
```

## Quick Start

### 1. Configure the SDK

Configure Attro on app launch:

```swift
import AttroSDK

@main
struct MyApp: App {
    init() {
        Attro.configure(organizationSlug: "ride-ios")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

### 2. Check Deferred Attribution

Call this on **every** launch (not just the first). It runs the network check only
until a *definitive* answer is recorded; after that it is a cheap no-op that
returns any stored attribution. If a check fails transiently (offline, or a 5xx
the backend flags as retryable), the SDK retries in-process with backoff and, if
that still fails, persists a durable pending-check flag so the **next launch
retries** instead of permanently losing attribution.

```swift
Task {
    do {
        if let attribution = try await Attro.checkAttribution() {
            print("Attributed to affiliate: \(attribution.affiliateId)")

            // If using RevenueCat, set attributes
            Attro.applyToRevenueCat(attribution)
        }
    } catch {
        // A thrown retryable error means a retry is already scheduled for the
        // next launch — safe to ignore here.
    }
}
```

> The deferred-match request sends the device's real Safari/WebKit User-Agent so
> the backend can match on browser family. A static User-Agent would degrade
> every match to IP-only, which no longer auto-attributes by default.

### 3. Handle Universal Links

Parse attribution from Universal Links:

```swift
.onOpenURL { url in
    if let attribution = Attro.parseUniversalLink(url) {
        Attro.storeAttribution(attribution)
        Attro.applyToRevenueCat(attribution)
    }
}
```

### 4. Refer-a-Friend

Get a user's referral link and stats:

```swift
let referral = try await Attro.getMyReferral(userId: currentUser.id)

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
import AttroSDK

@main
struct RideApp: App {
    init() {
        Attro.configure(organizationSlug: "ride-ios")
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
        if let attribution = Attro.parseUniversalLink(url) {
            Attro.storeAttribution(attribution)
            Attro.applyToRevenueCat(attribution)
        }
    }

    private func checkAttribution() async {
        do {
            if let attribution = try await Attro.checkAttribution() {
                Attro.applyToRevenueCat(attribution)
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
            referral = try? await Attro.getMyReferral(userId: userId)
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

If you're using RevenueCat, AttroSDK can automatically set subscriber attributes.

> **Ordering matters.** You must call `Purchases.configure(...)` **before**
> `Attro.applyToRevenueCat(...)`. If RevenueCat is not yet configured,
> `applyToRevenueCat` is a logged no-op (it returns `false`) rather than a crash,
> so attribution is simply dropped. Configure RevenueCat at app launch — in the
> same place you call `Attro.configure(...)`.

```swift
import AttroSDK
import RevenueCat

// 1. Configure RevenueCat first.
Purchases.configure(withAPIKey: "appl_xxx")

// 2. After getting attribution, apply it. Returns false (no-op) if RevenueCat
//    was somehow not configured.
if let attribution = try await Attro.checkAttribution() {
    Attro.applyToRevenueCat(attribution)
}
```

This sets the following subscriber attributes:
- `$rd_click_id`
- `$rd_affiliate_id`
- `$rd_offer_id`
- `$rd_project_id` (and `$rd_org_id` transitionally, for older backends)
- `$rd_tracking_code`
- `$rd_attributed_at`

## Universal Links Setup

To receive Universal Links, configure your app:

1. **Add Associated Domains** in your app's entitlements:
   ```
   applinks:get-attro.com
   ```

2. **Handle incoming URLs** using SwiftUI's `onOpenURL` or UIKit's scene delegate

## API Reference

### Configuration

```swift
// Basic configuration
Attro.configure(organizationSlug: "your-org")

// With custom base URL (for staging)
Attro.configure(
    organizationSlug: "your-org",
    baseURL: URL(string: "https://staging.get-attro.com")!
)

// Full configuration
Attro.configure(Configuration(
    organizationSlug: "your-org",
    baseURL: URL(string: "https://get-attro.com")!,
    allowedHosts: ["custom.domain.com"]
))
```

### Attribution

```swift
// Check deferred attribution. Call this on EVERY launch — it performs the
// network check only until a definitive matched/no-match answer is recorded,
// then becomes a cheap no-op. A transient failure is retried on a later launch,
// so it is not strictly "once per install".
let attribution = try await Attro.checkAttribution()

// Parse Universal Link
let attribution = Attro.parseUniversalLink(url)

// Check if URL is an Attro link
let isAttroLink = Attro.isAttroLink(url)

// Store attribution for later use. Prefer the awaitable variant when you read
// it back immediately afterwards (e.g. applyStoredAttributionToRevenueCat):
try await Attro.storeAttribution(attribution)

// Fire-and-forget variant (write happens in the background; failures are logged
// to the unified log under subsystem "com.attro.sdk", not silently dropped):
Attro.storeAttribution(attribution)

// Get stored attribution
let stored = await Attro.getStoredAttribution()
```

### Referrals

```swift
// Get referral info for a user
let referral = try await Attro.getMyReferral(userId: "user-uuid")

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
Attro.applyToRevenueCat(attribution)
```

## Error Handling

```swift
do {
    let referral = try await Attro.getMyReferral(userId: userId)
} catch AttroError.notConfigured {
    print("Call Attro.configure() first")
} catch AttroError.serverError(let code, let message, let retryable) {
    print("Server error \(code): \(message ?? "Unknown") (retryable: \(retryable))")
} catch AttroError.networkError(let error) {
    print("Network error: \(error)")
}
```

## Testing

For testing, you can reset the SDK state:

```swift
await Attro.reset()
```

## License

MIT License - see LICENSE file for details.

## Support

For issues and feature requests, please open an issue on GitHub.
