# Contract fixtures

Wire bodies of the Attro device endpoints, as the server sends them, so the
SDK is tested against real answers. `fixtures.json` names each fixture's
endpoint and status (or `"request": true` for a request body), and
`ContractTests` validates every fixture against the schema the vendored
contract (`../Contract/contract.json`) names for that endpoint and status.
A fixture that is not listed, or that its schema refuses, fails the tests.

| Fixture | Source in the Attro repository |
|---|---|
| `link-request.json` | `tests/api/device/attribution-routes.test.ts` (Universal Link body, with `?sub1=story`) |
| `link-attributed.json`, `code-attributed.json`, `match-attributed.json` | `src/lib/device/attribution-route.ts` `attributionResponse` (attributed) |
| `unknown-link.json`, `unknown-code.json`, `not-enabled.json` | `tests/api/device/attribution-routes.test.ts`, `tests/api/device/match-route.test.ts` (`toEqual` bodies) |
| `retryable-503.json` | `src/lib/device/attribution-route.ts` `retryableFailure` |
| `rate-limited-429.json` | `src/lib/device/request-auth.ts` `tooManyRequests` (plus the `Retry-After` header) |
| `unauthorized-app-key-401.json`, `unauthorized-token-401.json` | `src/lib/device/request-auth.ts`, `src/lib/device/attribution-route.ts` `appUserBinding` |
| `upgrade-required-426.json` | `src/lib/device/sdk-version.ts` `sdkVersionGate` (an `ios/1.9.9` header) |
| `my-affiliate-usd.json`, `my-affiliate-jpy.json` | `src/app/api/app/my-affiliate/route.ts`; Money values from `tests/api/device/my-affiliate-earnings-contract.test.ts` (`USD 1234 "12.34"`, `JPY 1500 "1500"`) |
| `referral-me.json` | `src/app/api/app/referral/me/route.ts` |

Contract: `docs/contracts/device-attribution.md` in the Attro repository; its
machine-readable files (`docs/contracts/device/`) are vendored in
`../Contract/` by `scripts/sync-contract.sh`. When the contract changes, sync
it, update these files from the same sources, and run `swift test`.
