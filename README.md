# AttroSDK

Swift package for attributing iOS in-app purchases to Attro affiliates.

The wire contract is Attro's `docs/contracts/device-attribution.md` (the
"contract" below); its machine-readable schemas are vendored in
`Tests/AttroSDKTests/Contract/` and the tests hold the SDK to them. This README is the integration checklist around it and
never overrides it.

## How attribution works

**Deterministic first. The server decides.** The app never tells Attro which
affiliate, offer or project to credit. It reports a signal, the server checks
it and stores an attribution row, and the app only carries that row's id to
RevenueCat as one subscriber attribute, `attro_attribution_id`.

| Signal | When | SDK call |
|---|---|---|
| Universal Link | Every open by a link, including when the app is already installed | `Attro.handleUniversalLink` |
| Typed affiliate code | The user types a code | `Attro.submitCode` |
| App Store offer code | The user redeems an offer code named after the affiliate's code | none: RevenueCat reports `offer_code` |
| Probabilistic match (opt-in) | First launch, only if the project opted in | `Attro.matchInstall` |

A probabilistic answer never replaces a deterministic one. A customer's first
attributed purchase binds the customer to that affiliate for good, and renewals
pay through their original purchase: the attribute is only a pointer.

## Requirements

- iOS 15.0+ (macOS 12.0+ builds, for tests)
- Swift 5.9+ / Xcode 15+
- RevenueCat `purchases-ios` 5.x, if you use the `AttroRevenueCat` product

## Installation (Swift Package Manager)

In Xcode: **File → Add Package Dependencies**, enter
`https://github.com/We-Are-Empire/attro-ios-sdk.git`, choose
**Up to Next Major Version** from `2.0.0`, and add:

- `AttroSDK` (always), and
- `AttroRevenueCat` if the app uses RevenueCat (it brings in `purchases-ios-spm`).

Or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/We-Are-Empire/attro-ios-sdk.git", from: "2.0.0"),
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "AttroSDK", package: "attro-ios-sdk"),
            .product(name: "AttroRevenueCat", package: "attro-ios-sdk"),
        ]
    ),
]
```

Both products ship a privacy manifest (`PrivacyInfo.xcprivacy`); see
[Privacy](#privacy).

## 1. Set up the project in Attro

In the Attro admin, **Project → Integrations**:

1. **App identity.** Enter your Apple Team ID and bundle ID. A platform admin
   verifies that you own the App Store app before the identity is published in
   the AASA file (contract §2). Until then links open Safari, not your app.
2. **Keys** (contract §1). Generate the **App key** and ship it in the app
   (`x-api-key`; it authorizes device endpoints only and is assumed
   extractable). The **Server key** is for your backend only: never put it in
   the app.
3. **RevenueCat.** Connect RevenueCat and paste the connection's webhook URL and
   Authorization key into RevenueCat (**Project settings → Integrations →
   Webhooks**). Send a test event.
4. **Probabilistic install matching** stays off unless you accept IP +
   User-Agent matching and show your users the admin's disclosure (contract
   §3.3).

Note the project's **public slug** (the `<public_slug>` in its links) and any
custom link domain.

## 2. Associated Domains

Add the Associated Domains capability with the host your links use:

```
applinks:get-attro.com          // platform links: https://get-attro.com/a/<public_slug>/<code>
applinks:go.example.com         // custom domain links: https://go.example.com/r/<code>
```

On the platform domain your app claims only `/a/<your public_slug>/*`. A
hand-typed `https://get-attro.com/r/<code>` never opens an app; it records the
click in the browser. Links are handed out by Attro (portal, admin,
`AffiliateInfo.trackingLink.url`): never build them by hand.

## 3. Configure at launch

Configure RevenueCat first, then Attro:

```swift
import AttroSDK
import AttroRevenueCat
import RevenueCat

@main
struct YourApp: App {
    init() {
        Purchases.configure(withAPIKey: "appl_...")
        Attro.configure(Attro.Configuration(
            appKey: AppConfig.attroAppKey,       // the project's App key
            publicSlug: "your-program",          // the project's public slug
            customDomains: ["go.example.com"]    // only if you use one
        ))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    Task { try? await Attro.handleUniversalLink(url) }
                }
                .task {
                    await Attro.retryPendingAttributions()
                    await Attro.applyCurrentAttributionToRevenueCat()
                    _ = try? await Attro.matchInstall()   // no-op unless opted in
                }
        }
    }
}
```

`Configuration`:

| Field | Default | Purpose |
|---|---|---|
| `appKey` / `project.appKey` | required | The project's App key (`x-api-key`). |
| `publicSlug` | `nil` | The project's public slug. When nil, any `/a/<slug>/<code>` on the platform host is accepted for this project (the server still resolves the code in the key's project only). |
| `customDomains` | `[]` | The project's custom link hosts (`/r/<code>` links). |
| `additionalProjects` | `[]` | Other projects of the same organization this app serves; a link is sent with the key of the project whose slug or domain it carries. |
| `baseURL` | `https://get-attro.com` | Attro's base URL; its host is the platform link domain. |
| `probabilisticMatching` | `false` | Call the opt-in probabilistic match (see step 6). |
| `appUserTokenProvider` | `nil` | User-token mode (see step 7). |

`configure` is last-write-wins: configure once, with everything.

## 4. Universal Links

Call `handleUniversalLink` for every open by a link, including when the app is
already installed:

```swift
// AttroRevenueCat: uses Purchases.shared.appUserID and sets the attribute.
let outcome = try await Attro.handleUniversalLink(url)

// AttroSDK only: pass the RevenueCat app user id yourself.
let outcome = try await Attro.handleUniversalLink(url, appUserId: Purchases.shared.appUserID)
```

- Returns `nil` (and sends nothing) when the URL is not one of your Attro links.
- Otherwise returns `.attributed(AttributionResult)` or
  `.notAttributed(reason)` (`unknownLink`, `rejected`, ...).
- UIKit apps: handle `scene(_:continue:)` and, for a cold start,
  `connectionOptions.userActivities` in `scene(_:willConnectTo:options:)`,
  passing `userActivity.webpageURL`.

`Attro.parseUniversalLink(url)` / `Attro.isAttroLink(url)` parse without any
network call.

## 5. Typed codes

```swift
let outcome = try await Attro.submitCode(codeTextField.text ?? "")
switch outcome {
case .attributed: showCodeAccepted()
case .notAttributed(.unknownCode): showCodeNotFound()
case .notAttributed: showCodeNotFound()
}
```

Matching is exact and case-insensitive on the server. Typed codes are limited to
10 guesses a minute per install: expect `AttroError.rateLimited(retryAfter:)`.

App Store **offer codes** need no app code: name the offer code so that the
identifier RevenueCat reports as `offer_code` equals the affiliate's code.

## 6. Probabilistic install match (opt-in)

Only when the project turned on **Probabilistic install matching** and your app
shows the disclosure:

```swift
Attro.configure(Attro.Configuration(appKey: ..., publicSlug: ..., probabilisticMatching: true))
_ = try? await Attro.matchInstall()   // at launch
```

The SDK sends only the install id, the app user id (and token) and the app's
WebKit User-Agent (read once from `WKWebView` and cached per OS version). It
collects no screen size, time zone or language. The match runs once per install
and is skipped when the install already has a deterministic attribution. On a
shared public IP it can credit the wrong affiliate: the admin disclosure says
so.

## 7. RevenueCat attribute and app user ids

Exactly one attribute is set: `attro_attribution_id` = the id of the current
attribution (contract §4). Set it **before presenting the paywall**; RevenueCat
syncs attributes on configure, on backgrounding and on purchase.

```swift
await Attro.applyCurrentAttributionToRevenueCat()   // AttroRevenueCat

// or, by hand:
if let current = await Attro.currentAttribution() {
    Purchases.shared.attribution.setAttributes(current.subscriberAttributes)
}
```

Every attribution is bound for good to the RevenueCat app user id at the time
of the touch, and only a purchase by that user (or its aliases) is attributed.

- Use unguessable app user ids (RevenueCat's anonymous ids or random UUIDs),
  never sequential ids or emails.
- If your app user ids are your own account ids or emails, turn on
  **user-token mode** for the project. Your backend gets a token for the
  signed-in user from `POST /api/app/user-token` (Server key,
  `{ appUserId }`, valid one hour), and the SDK sends it:

```swift
Attro.configure(Attro.Configuration(
    appKey: ..., publicSlug: ...,
    appUserTokenProvider: { appUserId in
        try await YourBackend.attroUserToken(for: appUserId)   // never cache past expiry
    }
))
```

A `401` (`AttroError.unauthorized`) means a missing, expired or foreign token or
key: do not retry with the same token.

## 8. Retries

A transient failure (offline, `503 { retryable: true }`, `429`) throws an error
whose `isRetryable` is true. The SDK keeps the attempt with its original
`requestId`, so resending it replays the server's answer instead of recording a
second click. Call `Attro.retryPendingAttributions()` at launch and when the
app becomes active, then `applyCurrentAttributionToRevenueCat()`.

## 9. Refer-a-friend

Needs an identity provider enrolled for the project (**Admin → Login
providers**) and a fresh access token of the signed-in user.

```swift
let me = try await Attro.getMyAffiliate(accessToken: session.accessToken, provider: "your-idp")
me.trackingLink.url                 // the Universal Link to share
me.stats.earnings                   // Money: exact, in the program currency
me.stats.earningsFormatted          // the server's display string, e.g. "$12.50"
me.shareContent.text

let program = try await Attro.getReferralProgram(accessToken: session.accessToken, provider: "your-idp")
program.shareUrl                    // render a QR from this
program.stats.tokenBalance          // "N credits"
program.defaultReward?.fulfillmentData?.discountPercent
```

Redeeming a credit is a backend call with the Server key (contract §7), never
from the app.

## Money

Every amount the SDK decodes is a `Money` value, never a `Double`:

```json
{ "amount": "12.50", "amountMinor": 1250, "currency": "USD" }
```

`Money.amount` is an exact `Decimal` parsed from the string,
`amountMinor` an `Int64`, and `minorUnitExponent` the digits the server used
(0 for JPY). A payload whose `amount` is a JSON number, whose `amountMinor` is
not an integer, or whose two fields disagree fails to decode
(`AttroError.decodingError`). Display with `earningsFormatted` or
`Money.formatted(locale:)`.

## Errors

| Error | Meaning | Retry? |
|---|---|---|
| `notConfigured` | `Attro.configure` has not run | no |
| `unauthorized(message:)` | `401`: bad app key or `appUserToken` | no, not with the same token |
| `rateLimited(retryAfter:)` | `429`, with `Retry-After` seconds | later (kept pending) |
| `serverError(statusCode:message:retryable:)` | other non-2xx; `503` is retryable; `426` means this SDK version is no longer supported (update the package) | if `retryable` |
| `networkError` | offline, timeout | yes (kept pending) |
| `decodingError` | response outside the contract | no |
| `missingParameter` / `invalidParameter` | bad input (empty or too long) | no |
| `appUserTokenUnavailable` | your token provider threw | yes |
| `revenueCatNotConfigured` | `AttroRevenueCat` called before `Purchases.configure` | no |

## Privacy

`AttroSDK` ships `PrivacyInfo.xcprivacy`:

- **Collected, linked to the user, not used for tracking:** Device ID (the
  install id: a random UUID the SDK creates and keeps in the Keychain,
  this device only; not the IDFA and not derived from device properties), User
  ID (the RevenueCat app user id, and the user token in user-token mode;
  refer-a-friend sends the user's access token), Product Interaction (that a
  link was opened or a code typed). Purposes: developer's marketing (affiliate
  attribution) and app functionality (refer-a-friend).
- **Tracking:** `NSPrivacyTracking` is false and the SDK contacts no tracking
  domain. It does not read the IDFA and needs no App Tracking Transparency
  prompt.
- **Required-reason API:** UserDefaults (`CA92.1`) for the SDK's own state.
- **No fingerprinting:** no screen size, time zone, locale, boot time, disk
  space, keyboards or file timestamps. The opt-in probabilistic match (off by
  default) sends the WebKit User-Agent; the server compares it and the request
  IP with a click on the tenant's download page. If you turn it on, review your
  App Store privacy answers and disclosure.

`AttroRevenueCat` collects nothing itself.

Mirror these in your App Store Connect privacy answers.

## Testing

1. **Universal Link:** open a platform link on a device with the app installed.
   `handleUniversalLink` returns `.attributed` with `source == .universalLink`,
   and RevenueCat shows `attro_attribution_id` on the customer.
2. **Typed code:** submit an affiliate code; expect `source == .code`.
3. **Purchase:** make a sandbox purchase (Attro records sandbox conversions
   only in environments with `ALLOW_SANDBOX_CONVERSIONS=true`).
4. **Links open Safari:** check the app identity is verified, the entitlement
   names the link's host, and
   `https://<host>/.well-known/apple-app-site-association` lists your app ID.

`await Attro.reset()` clears the SDK's stored state (not the Keychain install
id).

Run the package's own tests with `swift test`.

## Versioning and the contract

Every request the SDK makes carries `X-Attro-SDK: ios/<version>` (for this
release `ios/2.0.0`) and calls the device endpoints under `/api/app/*`
(contract §8). Attro counts the SDK versions each project sees and answers
`426` `SDK_UPGRADE_REQUIRED` to a version below the oldest one it still
supports (the SDK logs it), so keep the package within its major version.

`Tests/AttroSDKTests/Contract/` is a copy of Attro's
`docs/contracts/device/` (the contract manifest, one JSON Schema per request
and response, and `CHECKSUMS.sha256`). `ContractTests` checks the copy
against its checksum list, validates every fixture
(`Tests/AttroSDKTests/Fixtures/fixtures.json` names its endpoint and status)
and the body of every request the SDK sends against those schemas, and checks
that every path the SDK calls is a canonical iOS endpoint. To pick up a
contract change:

```sh
scripts/sync-contract.sh <path to an Attro checkout>   # copy and verify
swift test
scripts/sync-contract.sh --check <path>                # CI-style: fails if the copy is stale
```

The sync prints the digest of the checksum list; Attro records it in
`docs/contracts/sdk-pins.json`, and an Attro test fails when Attro's
contract moves past the copy this SDK vendors.

## Migrating from 1.x

2.0 implements the current contract; the 1.x contract no longer exists on the
server. See [CHANGELOG.md](CHANGELOG.md) for every change. In short:

- `Configuration(organizationSlug:...)` → `Configuration(appKey:publicSlug:...)`.
- `checkAttribution()` (fingerprint match) → deterministic
  `handleUniversalLink` / `submitCode`, plus opt-in `matchInstall()`.
- `parseUniversalLink(url)` returns an `AttroLink` (no client-side affiliate
  ids); report it with `handleUniversalLink`.
- `applyToRevenueCat(Attribution)` with `$rd_*` attributes →
  `applyCurrentAttributionToRevenueCat()` setting `attro_attribution_id`.
- `getMyReferral(userId:orgSlug:)` → `getMyAffiliate(accessToken:provider:)`,
  with `stats.earnings` as `Money`.

## License

MIT. See [LICENSE](LICENSE).
