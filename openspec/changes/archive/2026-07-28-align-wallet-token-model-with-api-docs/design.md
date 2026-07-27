## Context

The published Swagger 2.0 definition for `wallet-api_internal_wallet.Token` includes four nullable market-metadata properties that are not consistently represented by the iOS client: `change24hPercent` and `marketCapUSD` are JSON numbers, `coinKey` is a string, and `marketDataUpdatedAt` is an ISO 8601 timestamp string. The current transport DTO omits three properties and the working tree temporarily removes the required `coinKey` to tolerate current responses.

Token responses are decoded into `WalletToken`, which currently combines shared token metadata with wallet-specific `rawBalance` and `balance`. `WalletStore` then encodes complete `[WalletToken]` and `TokenPortfolio` values into SwiftData blobs. That duplicates metadata across wallets and means adding fields to `WalletToken` implicitly changes every cached blob.

The revised design normalizes persistence: shared token metadata is cached once by a stable symbol/address key, while balances are cached separately by wallet address and that same key. Cached `WalletToken` values are projections composed at load time. Existing fractional-ISO-8601 parsing work in the working tree must be preserved.

## Goals / Non-Goals

**Goals:**

- Represent every documented nullable token market-metadata field in transport and domain models.
- Give token metadata and wallet balances the same deterministic matching key derived from token symbol and normalized token address.
- Persist token metadata without `rawBalance` or `balance`.
- Persist balances with their wallet address, token key, exact values, and portfolio position.
- Recompose cached wallet tokens by joining balances for the requested wallet to matching shared metadata.
- Replace and purge one wallet's balance records without deleting shared token metadata or another wallet's balances.
- Preserve native-token snapshot order and return native metadata with its API-defined zero balance.

**Non-Goals:**

- Displaying 24-hour change, market capitalization, or market-data freshness in the UI.
- Changing wallet API endpoints, query parameters, error payloads, portfolio or transaction wire models.
- Introducing general-purpose relational abstractions or SwiftData relationships.
- Migrating data out of the previous opaque cache payloads.
- Generating Swift models from Swagger or adding a dependency.

## Decisions

1. **Use optional value-semantic domain properties for documented market data.** `WalletToken` will expose `change24hPercent: Decimal?`, `coinKey: String?`, `marketCapUSD: Decimal?`, and `marketDataUpdatedAt: Date?`. `Decimal` avoids binary floating-point loss and `Date` keeps wire formatting out of downstream code. `Double` was rejected because it would add avoidable financial rounding.

2. **Derive identity and matching from symbol plus token address.** `WalletToken.key` will combine `symbol` with the lowercased `tokenAddress`, or the literal `native` when the address is absent; `id` will return the same value. `coinKey` remains optional API metadata and does not participate in identity. This follows the requested join semantics and keeps nullable enrichment data from destabilizing cache keys.

3. **Keep wire decoding in the private DTO mapper.** `TokenDTO` will decode the two JSON numbers as optional `Decimal`, `coinKey` as `String?`, and the market timestamp as `String?`; `makeToken` will copy values and reuse the existing standard/fractional ISO 8601 parser. Malformed non-null values remain invalid response data rather than being silently dropped.

4. **Use explicit normalized cache records without SwiftData relationships.** A unique `TokenCacheRecord` will store the token key and a Codable metadata payload containing every `WalletToken` field except `rawBalance` and `balance`. A unique `TokenBalanceCacheRecord` will store a composite record key, normalized wallet address, token key, raw balance, decimal balance, and position. The composite key prevents duplicate balances for the same wallet/token pair; position preserves API order. Explicit string keys make joins and purge predicates simple and avoid relationship lifecycle behavior.

5. **Retain snapshot records as versioned indexes.** `NativeTokensCacheRecord.payload` will contain a versioned ordered list of token keys. `PortfolioCacheRecord.payload` will contain versioned portfolio-level values such as API `fetchedAt` and `network`, while its existing `fetchedAt` remains the local cache timestamp. Portfolio membership and order come from wallet balance records. The current record shapes stay usable while their opaque payload semantics become explicit.

6. **Normalize writes in one SwiftData transaction.** Saving native tokens upserts their metadata records and replaces the ordered native snapshot. Saving a portfolio upserts shared metadata, removes prior balance records for that wallet, inserts the new ordered balance set, and replaces the portfolio header before one `modelContext.save()`. Any failure rolls back the complete update.

7. **Compose reads by key and fail closed on incomplete joins.** Loading native tokens resolves the ordered snapshot keys to metadata and supplies zero balances. Loading a portfolio fetches only balances for the requested wallet, sorts by position, resolves each token key to metadata, and builds `WalletToken` values. An unrecognized snapshot version, malformed payload, or missing metadata makes that snapshot unusable; the store discards the affected snapshot (and wallet balances for an invalid portfolio) and returns a cache miss instead of a partial portfolio.

8. **Purge only address-owned data.** Address purge will delete the wallet's portfolio header, transaction pages, and token-balance records. Shared token metadata, the native snapshot, and other wallets' balances remain because they are not owned by the purged address. Unreferenced metadata cleanup is intentionally deferred.

9. **Limit downstream domain changes to compatibility.** Test doubles, previews, and samples will supply the aligned initializer fields. `TokenViewModel` will not start displaying or otherwise consuming the new market metadata in this change.

## Risks / Trade-offs

- **[Risk] Symbol/address keys collide if the API emits two logical tokens with the same pair** → Follow the explicit contract and normalize only address casing; cover native and contract-address keys in tests.
- **[Risk] Shared metadata is overwritten by the last saved snapshot** → Treat token metadata as global enrichment keyed by token identity; balances remain isolated by wallet.
- **[Risk] A missing metadata row could produce a partial wallet** → Invalidate the affected snapshot and return a cache miss instead of dropping individual tokens.
- **[Risk] Replacing portfolio balances can leave stale rows after a failed save** → Perform delete, insert, and header replacement before one model-context save and roll back on failure.
- **[Risk] Existing cache blobs do not match versioned snapshot payloads** → Treat them as disposable cache misses and lazily invalidate them; remote refresh repopulates normalized records.
- **[Risk] New initializer fields create fixture churn** → Make only mechanical fixture updates required for compilation and preserve each fixture's existing behavior.

## Migration Plan

1. Add the documented optional fields and symbol/address key to `WalletToken`, then align the response DTO and mapper.
2. Add shared token-metadata and wallet-balance SwiftData models to `WalletCacheSchema`.
3. Change native and portfolio cache writes to normalized records and versioned snapshot payloads.
4. Change native and portfolio cache reads to key-based composition and invalid-cache handling.
5. Extend address purge to remove wallet balances while retaining shared metadata.
6. Update fixtures and run focused API/model/store tests, then the full suite and simulator build.

No legacy payload migration is attempted. Old or corrupt native/portfolio payloads are removed when read and treated as cache misses. Rollback consists of reverting the schema and store changes; the cache remains disposable and can be repopulated remotely.

## Open Questions

None. Metadata garbage collection and UI consumption are intentionally deferred.
