## 1. Contract and Persistence Tests

- [x] 1.1 Add token-response tests that decode populated `change24hPercent`, `coinKey`, `marketCapUSD`, and fractional `marketDataUpdatedAt` values and assert exact domain mapping.
- [x] 1.2 Add response tests showing explicit-null and omitted market metadata decode as `nil`, while wrong numeric types and malformed market timestamps produce `APIError.invalidData`.
- [x] 1.3 Replace coin-key identity coverage with token-key tests for symbol plus normalized contract address, native fallback, and independence from `coinKey`.
- [x] 1.4 Add store tests proving shared metadata composes with wallet-isolated balances in saved order and native snapshots compose with zero balances.
- [x] 1.5 Add store tests for portfolio replacement, address purge retention, and invalid legacy or incomplete snapshot handling.

## 2. HTTP and Domain Model Alignment

- [x] 2.1 Add the four documented optional market-metadata properties to `WalletToken`, and make its key and ID derive from symbol plus normalized token address.
- [x] 2.2 Extend `TokenDTO` and `makeToken` to decode the documented JSON wire types and map them into `WalletToken`, reusing standard and fractional ISO 8601 parsing.
- [x] 2.3 Update existing test doubles, previews, samples, and other `WalletToken` construction sites for the aligned initializer without changing presentation behavior.

## 3. Normalized Token Cache

- [x] 3.1 Add shared token-metadata and wallet-balance cache records, versioned native and portfolio snapshot payloads, and register the new records in `WalletCacheSchema`.
- [x] 3.2 Update native-token cache save/load to upsert metadata, persist ordered token keys, and compose zero-balance wallet tokens.
- [x] 3.3 Update portfolio cache save/load to replace wallet balance rows atomically and compose ordered wallet tokens by joining balances to shared metadata keys.
- [x] 3.4 Extend address purge and invalid-cache handling to remove wallet-owned balances and unusable snapshots while retaining shared metadata and other wallets' data.

## 4. Verification

- [x] 4.1 Run focused wallet API, model, and store tests covering decoding, keys, normalized composition, isolation, replacement, purge, and invalidation.
- [x] 4.2 Run the full test suite and an iOS Simulator build to confirm the schema and model changes introduce no downstream regressions.
