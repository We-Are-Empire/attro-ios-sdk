# AttroSDK

A lightweight Swift Package for integrating Attro affiliate tracking into iOS apps.

## Features

- **Deferred Attribution** - Automatically match users to affiliate clicks on first app launch
- **Universal Link Handling** - Parse attribution from Universal Links
- **RevenueCat Integration** - Optional integration to set subscriber attributes
- **Refer-a-Friend** - Get referral codes, share links, and stats for logged-in users

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
        Attro.configure(Attro.Configuration(
            organizationSlug: "ride-ios",
            apiKey: Secrets.attroAppKey  // per-project app key, from the Attro admin
        ))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

`Configuration` fields:

| Field | Required | Purpose |
|-------|----------|---------|
| `organizationSlug` | yes | Your organization's slug (e.g. `"ride-ios"`) |
| `baseURL` | no | Attro API base URL (defaults to `https://get-attro.com`) |
| `allowedHosts` | no | Additional hosts to accept as Attro Universal Links (e.g. a custom tracking domain) |
| `apiKey` | for referrals | The **per-project app key** (`x-api-key`), minted in the Attro admin. Required only for the referral-program endpoints (`getReferralProgram`); the server resolves your org/project from it. Treat it as a secret — ship it via your app config, not source control. |

> **Warning:** `configure` is last-write-wins global state — each call replaces
> the entire stored configuration. The convenience overload
> `Attro.configure(organizationSlug:baseURL:)` builds a configuration with
> `apiKey: nil`, so calling it after (or instead of) the full form silently
> disables the referral endpoints. If you use `apiKey` or `allowedHosts`,
> configure once with a full `Configuration`.

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
> every match to IP-only, which no longer auto-attributes by default. It also
> sends the app's bundle identifier (`Bundle.main.bundleIdentifier`) so the
> backend can resolve which project the install belongs to.

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

Get a logged-in user's referral code, share link, and stats. This requires
`Configuration.apiKey` (the per-project app key) plus a **fresh** access token
from your identity provider — the backend derives the user from the verified
bearer token, so never pass a cached/expired token:

```swift
let referral = try await Attro.getReferralProgram(
    accessToken: session.accessToken,  // fresh upstream bearer token
    provider: "ride"                   // identity-provider slug enrolled in Attro
)

// Display stats
print("Completed referrals: \(referral.stats.completed)")
print("Pending referrals: \(referral.stats.pending)")
print("Credits: \(referral.stats.tokenBalance ?? referral.stats.tokensEarned)")

// Describe what a credit is worth (when the project configures it)
if let reward = referral.defaultReward,
   let percent = reward.fulfillmentData?.discountPercent {
    print("Each credit = \(percent)% off")
}

// Share referral link (render a QR from this URL on-device)
let url = referral.shareUrl
```

> The older `Attro.getMyReferral(userId:orgSlug:)` targets a retired backend
> contract and now returns 401 against every current deployment. It is
> deprecated — migrate to `getReferralProgram`.

## Complete Integration Example

```swift
import SwiftUI
import AttroSDK

@main
struct RideApp: App {
    init() {
        Attro.configure(Attro.Configuration(
            organizationSlug: "ride-ios",
            apiKey: Secrets.attroAppKey
        ))
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
    @State private var referral: ReferralProgramInfo?
    let accessToken: String  // fresh upstream bearer token for the logged-in user

    var body: some View {
        VStack(spacing: 16) {
            if let referral {
                Text("Your Referral Link")
                    .font(.headline)

                Text(referral.shareUrl)
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 24) {
                    StatView(value: referral.stats.completed, label: "Referrals")
                    StatView(value: referral.stats.pending, label: "Pending")
                    StatView(value: referral.stats.tokenBalance ?? 0, label: "Credits")
                }

                if let shareURL = referral.shareURL {
                    ShareLink(item: shareURL) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                ProgressView()
            }
        }
        .task {
            referral = try? await Attro.getReferralProgram(
                accessToken: accessToken, provider: "ride")
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
// Basic configuration (no apiKey — referral endpoints disabled)
Attro.configure(organizationSlug: "your-org")

// With custom base URL (for staging)
Attro.configure(
    organizationSlug: "your-org",
    baseURL: URL(string: "https://staging.get-attro.com")!
)

// Full configuration
Attro.configure(Attro.Configuration(
    organizationSlug: "your-org",
    baseURL: URL(string: "https://get-attro.com")!,
    allowedHosts: ["custom.domain.com"],
    apiKey: "your-per-project-app-key"  // from the Attro admin; enables getReferralProgram
))
```

`configure` may be called with either form, but it is **last-write-wins**: each
call replaces the whole configuration, and the convenience overload sets
`apiKey` to `nil`. Configure once, at launch, with everything you need.

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
// Get referral-program info for the logged-in user. Requires
// Configuration.apiKey and a FRESH upstream access token; `provider` is the
// identity-provider slug enrolled for your project in Attro.
let referral = try await Attro.getReferralProgram(
    accessToken: session.accessToken,
    provider: "ride"
)

// Access referral data
referral.code                   // Referral code (e.g. "abc12345")
referral.shareUrl               // Shareable URL (render a QR from this)
referral.shareURL               // Same, as a URL? convenience
referral.stats.completed        // Referrals that reached first paid invoice
referral.stats.pending          // Attributed but not yet completed
referral.stats.tokensEarned     // Tokens earned from completed referrals
referral.stats.tokensPending    // Tokens withheld pending completion
referral.stats.tokenBalance     // Current spendable balance (Int?; nil on older backends)
referral.defaultReward          // What a token redeems into (name, tokenCost,
                                // fulfillmentData.discountPercent), when configured
```

`Attro.getMyReferral(userId:orgSlug:)` is **deprecated**: it targets the retired
`/api/ios/my-affiliate` contract and 401s against current backends.

### RevenueCat (if available)

```swift
// Apply attribution to RevenueCat
Attro.applyToRevenueCat(attribution)
```

## Error Handling

```swift
do {
    let referral = try await Attro.getReferralProgram(
        accessToken: accessToken, provider: "ride")
} catch AttroError.notConfigured {
    print("Call Attro.configure() first")
} catch AttroError.missingParameter(let param) {
    print("Missing \(param) — e.g. no apiKey in the configuration")
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
