# Contract fixtures

Wire bodies of the Attro device endpoints, copied from the Attro repository
(branch `hardening/prod-ready`) so the SDK is tested against what the server
actually sends:

| Fixture | Source in the Attro repo |
|---|---|
| `link-request.json` | `tests/api/ios/attribution-routes.test.ts` (Universal Link body, with `?sub1=story`) |
| `link-attributed.json`, `code-attributed.json`, `match-attributed.json` | `src/lib/ios/attribution-route.ts` `attributionResponse` (attributed) |
| `unknown-link.json`, `unknown-code.json`, `not-enabled.json` | `tests/api/ios/attribution-routes.test.ts`, `src/app/api/ios/match/route.ts` (`toEqual` bodies) |
| `retryable-503.json` | `src/lib/ios/attribution-route.ts` `retryableFailure` |
| `rate-limited-429.json` | `src/lib/ios/request-auth.ts` `tooManyRequests` (plus the `Retry-After` header) |
| `unauthorized-app-key-401.json`, `unauthorized-token-401.json` | `src/lib/ios/request-auth.ts`, `src/lib/ios/attribution-route.ts` `appUserBinding` |
| `my-affiliate-usd.json`, `my-affiliate-jpy.json` | `src/app/api/ios/my-affiliate/route.ts`; Money values from `tests/api/ios/my-affiliate-earnings-contract.test.ts` (`USD 1234 "12.34"`, `JPY 1500 "1500"`) |
| `referral-me.json` | `src/app/api/ios/referral/me/route.ts` |

Contract: `docs/contracts/ios-attribution.md` in the Attro repository. When the
contract changes, update these files from the same sources.
