## Why

The wallet API now exposes `/v1/wallet/{address}` as the supported holdings route, with the same portfolio contract but broader token validation and no CoinGecko market enrichment. The app still requests the legacy `/v1/addresses/{address}/tokens` route and must migrate to the new route before the legacy integration is retired.

## What Changes

- **BREAKING** Replace wallet portfolio requests to `/v1/addresses/{address}/tokens` with `/v1/wallet/{address}` without a legacy-route fallback.
- Preserve the existing `TokenPortfolio` and `WalletToken` decoding contract, including optional market metadata whose null or omitted values remain `nil`.
- Preserve current cache policy and UI behavior, including the `-` placeholder for an absent 24-hour change.
- Update request coverage to require the new normalized wallet route.

## Capabilities

### New Capabilities

- `wallet-portfolio-api`: Defines the wallet holdings route, address normalization, response decoding, and behavior for unavailable market enrichment.

### Modified Capabilities

None.

## Impact

- Affected production code: `sevenwallet/Network/APIEndpoint.swift`.
- Affected tests: `sevenwalletTests/APIClientTests.swift`.
- External dependency: wallet API `GET /v1/wallet/{address}` and its existing `TokenPortfolio` response schema.
- No domain-model, repository, persistence, cache-version, or UI changes are required.
