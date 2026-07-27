## 1. Token-Market Contract Tests

- [x] 1.1 Add a response test that verifies the normalized endpoint path and exact mapping of a populated portfolio with independent CoinGecko and CoinMarketCap values.
- [x] 1.2 Add response tests showing documented nullable values accept explicit null and omission, plus model tests for contract and native token keys.
- [x] 1.3 Add response tests showing malformed decimals, timestamps, provider numeric types, missing structural values, and a mismatched returned wallet produce `APIError.invalidData`.

## 2. Domain and Transport Alignment

- [x] 2.1 Add the four independent token-market domain models with descriptive provider properties, exact value types, and wallet-token-compatible identity.
- [x] 2.2 Add the `/v1/tokens/{address}` endpoint and expose `fetchTokenMarkets(address:)` through the token remote data source protocol.
- [x] 2.3 Add private wire DTOs and strict mapping for required structure, documented nullable values, decimal strings, provider numbers, and standard or fractional portfolio timestamps.

## 3. Verification

- [x] 3.1 Run focused API and model tests covering populated, nullable, malformed, identity, path, and address-validation behavior.
- [x] 3.2 Run the full test suite and an iOS Simulator build to confirm the additive API support introduces no regressions.
