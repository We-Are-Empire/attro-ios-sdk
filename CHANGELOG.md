# Changelog

All notable changes to AttroSDK. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the package uses
[Semantic Versioning](https://semver.org/).

## [2.0.0] - Unreleased

Implements Attro's device attribution contract
(`docs/contracts/device-attribution.md`, contract version 2.2.0).
The 1.x contract (`$rd_*` subscriber attributes and client-described
affiliate, offer and project ids) is gone from the server: 1.x apps attribute
nothing. There is no backward compatibility.

### Breaking

- **Configuration.** `Configuration(organizationSlug:baseURL:allowedHosts:apiKey:)`
  and `configure(organizationSlug:baseURL:)` are removed. Use
  `Configuration(appKey:publicSlug:customDomains:baseURL:probabilisticMatching:appUserTokenProvider:)`,
  or `Configuration(project:additionalProjects:...)` for an app serving several
  projects. The App key is now required: every device endpoint needs it.
- **RevenueCat attribute.** The SDK sets exactly one subscriber attribute,
  `attro_attribution_id` (a server row id). The `$rd_click_id`,
  `$rd_affiliate_id`, `$rd_offer_id`, `$rd_project_id`, `$rd_org_id`,
  `$rd_tracking_code` and `$rd_attributed_at` attributes are no longer set
  (`$` keys are reserved by RevenueCat). `applyToRevenueCat(Attribution)` and
  `applyStoredAttributionToRevenueCat()` are replaced by
  `applyToRevenueCat(AttributionResult)` and
  `applyCurrentAttributionToRevenueCat()`.
- **Deterministic attribution.** `checkAttribution()` (the fingerprint match)
  is removed. Report Universal Link opens with
  `handleUniversalLink(_:appUserId:)` (`POST /api/app/attribution/link`) and
  typed codes with `submitCode(_:appUserId:publicSlug:)`
  (`POST /api/app/attribution/code`). Every call names the RevenueCat app user
  id, to which the attribution is bound.
- **Probabilistic match is opt-in.** `matchInstall(appUserId:)` calls
  `/api/app/match` only when `probabilisticMatching` is on, sends only the
  install id, app user id (and token) and the WebKit User-Agent, and never
  replaces a deterministic attribution. The SDK no longer collects screen
  size, time zone, language or bundle id for matching.
- **Universal Link format.** `parseUniversalLink(_:)` returns an `AttroLink`
  (`kind`, `publicSlug`, `code`, `url`) for
  `https://<platform>/a/<public_slug>/<code>` and
  `https://<custom-domain>/r/<code>` only. The platform's `/r/<code>` and
  `/app/track` are not Universal Links. Query-string affiliate ids are no
  longer read.
- **Attribution model.** `Attribution` (clickId, affiliateId, offerId,
  projectId, trackingCode, matchMethod) is replaced by `AttributionResult`
  (attributionId, source, receivedAt) and `AttributionOutcome`.
  `storeAttribution`/`getStoredAttribution` are replaced by
  `currentAttribution()`; v1 stored state is deleted on `configure`.
- **Refer-a-friend.** `getMyReferral(userId:orgSlug:)` and `ReferralInfo` are
  removed. Use `getMyAffiliate(accessToken:provider:)`, which returns
  `AffiliateInfo`. `stats.earnings` is a `Money` object
  (`{ amount: "12.50", amountMinor: 1250, currency: "USD" }`) plus
  `stats.earningsFormatted`; it was a `Double`.
- **Errors.** `AttroError.invalidUniversalLink` and `.alreadyChecked` are
  removed; `.unauthorized`, `.rateLimited(retryAfter:)`, `.invalidParameter`,
  `.appUserTokenUnavailable` and `.revenueCatNotConfigured` are added.

### Added

- `Money`: exact decoding of every money field (decimal string + integer minor
  units, cross-checked; JSON numbers refused).
- User-token mode: `appUserTokenProvider` supplies `appUserToken`.
- Several projects per app (`additionalProjects`): links use the key of the
  project whose slug or custom domain they carry.
- Durable retries: a transient failure keeps the attempt with its `requestId`;
  `retryPendingAttributions()` resends it so the server replays instead of
  counting twice.
- `AttroRevenueCat` wrappers `handleUniversalLink(_:)`, `submitCode(_:)` and
  `matchInstall()` that read `Purchases.shared.appUserID` and set the
  attribute.
- Install id: an SDK-generated UUID in the Keychain (this device only).
- `PrivacyInfo.xcprivacy` privacy manifests for `AttroSDK` and
  `AttroRevenueCat`.
- `LICENSE` (MIT) and this changelog.
- Tests against fixtures copied from the Attro contract tests, each
  validated against the contract's JSON Schemas, vendored with a checksum
  list in `Tests/AttroSDKTests/Contract/` (`scripts/sync-contract.sh`). The
  body of every request the SDK sends is validated against its endpoint's
  request schema, and every path it calls is checked against the contract.
- `X-Attro-SDK: ios/2.0.0` on every request, so Attro can count the SDK
  versions in use and refuse retired ones (`426 SDK_UPGRADE_REQUIRED`, logged
  by the SDK and surfaced as a non-retryable `serverError`).

### Changed

- The device endpoints are called under `/api/app/*`, the contract's
  canonical paths (`/api/ios/*` are deprecated aliases on the server).
- Requests use an ephemeral `URLSession` (no cookies, no cache) and the SDK's
  own User-Agent `AttroSDK/2.0.0 (<bundle id>; iOS <version>)`, except the
  opt-in match, which sends the WebKit User-Agent as the contract requires.
- `ReferralProgramInfo` tolerates free-form `fulfillment_data`.
- `Package.resolved` pins `purchases-ios-spm` 5.91.0 (5.59.2 does not build
  with Xcode 27). The requirement is unchanged (`from: "5.0.0"`).

## [1.0.0]

Initial release (the retired `$rd_*` contract).
