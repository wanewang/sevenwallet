## Why

The API now publishes a separate cached token-market endpoint whose provider-specific response shape is not represented by the iOS client. The client needs an exact, independently callable model for that contract without replacing the existing holdings flow.

## What Changes

- Add domain models for token-market portfolios, tokens, CoinGecko data, and CoinMarketCap data.
- Add `/v1/tokens/{address}` as a separate API endpoint and expose it through the token remote data source.
- Decode documented strings into `Decimal` values and the portfolio timestamp into `Date`, while accepting null or omitted values only where Swagger marks a property nullable.
- Give market tokens the same symbol-and-normalized-address key used by existing wallet tokens.
- Keep the existing holdings endpoint, repository, cache, and UI behavior unchanged.
- Add contract tests for populated, nullable, malformed, address-mismatch, and endpoint-path behavior.

## Capabilities

### New Capabilities

- `token-market-api`: Models and decodes the cached provider-specific token-market response and exposes its endpoint through the remote data source.

### Modified Capabilities

None.

## Impact

- Affects wallet API domain models, endpoint routing, token remote-data-source decoding, and API contract tests.
- Does not affect the current portfolio repository, persistence schema, cache behavior, external dependencies, or user-facing views.
