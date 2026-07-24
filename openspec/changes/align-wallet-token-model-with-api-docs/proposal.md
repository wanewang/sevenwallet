## Why

The wallet API now documents optional token market metadata that the iOS HTTP and domain models do not represent consistently. The current cache also duplicates complete wallet-token payloads per wallet, coupling shared token metadata to wallet-specific balances and making the newly documented data difficult to preserve coherently.

## What Changes

- Add the documented optional token fields `change24hPercent`, `coinKey`, `marketCapUSD`, and `marketDataUpdatedAt` to the decoded and domain token models.
- Decode JSON number fields without converting them through binary floating-point, and parse the market-data timestamp with the same ISO 8601 support used by other API dates.
- Give every token a deterministic matching key derived from its symbol and normalized token address, independent of nullable API metadata such as `coinKey`.
- Normalize token persistence into shared token-metadata records without balances and wallet-specific token-balance records containing the wallet address and token matching key.
- Recompose cached `WalletToken` values by loading balances for the requested wallet and joining each balance to shared token metadata by matching key.
- Replace and purge wallet balances independently while retaining token metadata shared by other wallets and the native-token snapshot.
- Add decoding, key, cache-composition, wallet-isolation, replacement, and purge coverage.
- Keep endpoint paths, remote portfolio and transaction shapes, and UI presentation behavior unchanged.

## Capabilities

### New Capabilities

- `wallet-token-market-metadata`: Defines API market-metadata decoding, stable token matching keys, normalized token and balance caching, and cached wallet-token composition.

### Modified Capabilities

None.

## Impact

- Affects `WalletToken`, token response DTO mapping, SwiftData cache records and schema, `WalletStore`, and test/sample token construction sites.
- Replaces cached complete token and portfolio blobs with versioned snapshot metadata, shared token metadata, and wallet-specific balances; existing cache blobs are disposable and will be invalidated rather than migrated.
- Requires decoder, model, and persistence tests to cover the published API schema and normalized-cache behavior.
- Does not change the remote API, request endpoints, external dependencies, transaction caching, or user-facing views.
