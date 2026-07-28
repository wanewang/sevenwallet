## Context

`TokenRemoteDataSource` already decodes `/v1/tokens/{address}` into provider-preserving `TokenMarketPortfolio` values, but `TokenRepositoryProtocol` and `WalletHomeViewModel` do not consume that operation. The home view currently converts each cache-first portfolio event directly into `TokenViewModel` rows and considers the load complete when the portfolio stream finishes. The same repository protocol is also consumed by the wallet list, so placing enrichment inside `portfolio(address:policy:)` would unintentionally add market calls to every saved-wallet row.

The existing token-market domain contract keeps CoinGecko and CoinMarketCap values independent. This feature must retain that transport/domain behavior while applying the product-approved CoinGecko-first choice only when constructing home presentation values.

## Goals / Non-Goals

**Goals:**

- Run one token-market stage after a selected-wallet portfolio stream succeeds.
- Enrich the final portfolio values deterministically without changing holdings membership, balances, order, identity, or logos.
- Retry only transient market failures with cancellable 0.5-second and 1-second backoff.
- Keep holdings usable and provide clear loading, failure, and recovery behavior when enrichment is unavailable.
- Make sequencing, retry timing, enrichment, and cancellation independently testable.

**Non-Goals:**

- Changing token-market DTOs or provider-preserving domain models.
- Adding market enrichment to native tokens or wallet-list rows.
- Persisting or sharing market responses across loads.
- Retrying portfolio requests or changing the portfolio cache policy.
- Averaging providers or exposing provider selection controls.

## Decisions

### Expose token markets through the existing token repository boundary

Add an asynchronous `tokenMarkets(address:)` operation to `TokenRepositoryProtocol`. The concrete repository delegates to the existing remote method, owns the retry policy, and returns the decoded `TokenMarketPortfolio` without reading or writing `WalletStore`. `WalletHomeViewModel` is the only production caller added by this change.

Putting market enrichment inside `portfolio(address:policy:)` was rejected because it would affect the wallet list and couple persisted holdings refreshes to optional market availability. Injecting the remote data source directly into the home view model was rejected because retry policy belongs at the data boundary and would bypass the repository abstraction used by fixtures and tests.

### Sequence enrichment after the portfolio stream completes

While consuming the selected-wallet portfolio stream, retain the most recently emitted `[WalletToken]` and continue publishing cached and fresh rows according to current behavior. Only after the stream finishes successfully and emitted a portfolio does the home view model call `tokenMarkets(address:)`. A cached-then-fresh stream therefore produces one market request against the final holdings; a cached-only stream also produces one request. A failed or empty portfolio stream does not start market loading.

Native-token loads return after their existing stream and never request token markets. Pull-to-refresh continues using the policy selected by `PullRefreshCoordinator`; Retry continues using the existing `.ifExpired` portfolio policy. Both actions then run the same market stage after the portfolio stage succeeds.

### Enrich immutable holdings by their shared key

Build a market lookup by `TokenMarket.id`, which shares the existing symbol plus normalized-address/native identity with `WalletToken`. Map the final portfolio in its original order and construct a copy only for matched tokens. Token identity, balance fields, metadata, and logo remain sourced from the portfolio. Market-only values are ignored, and unmatched holdings remain unchanged.

For each display field independently, choose CoinGecko first and CoinMarketCap second. A chosen non-null market price replaces `WalletToken.priceUSD`; a chosen non-null change replaces `WalletToken.change24hPercent`. If neither provider supplies a field, retain the portfolio field. Provider objects remain unchanged and independent in `TokenMarketPortfolio`; the precedence exists only in the home enrichment mapping.

### Keep retry policy narrow, bounded, and testable

The repository performs at most three market attempts. It retries `APIError.transport`, `APIError.nonHTTPResponse`, HTTP 408, HTTP 429, and HTTP 5xx. It fails immediately for invalid requests, invalid data, all other HTTP statuses, and non-API errors. Before retry one it waits 0.5 seconds; before retry two it waits 1 second.

Inject a small asynchronous delay closure into `TokenRepository` with a production default backed by `Task.sleep`. Tests can record durations and return immediately. Both the sleep and request loop remain cancellation-aware, and cancellation is never converted into a retryable market failure.

### Treat market failure as non-blocking home state

The existing token loading indicator becomes true before awaiting token markets and remains true across attempts and backoff. Success publishes enriched rows, clears errors, and ends loading. Exhausted or non-retryable failure leaves the portfolio rows intact, ends loading, and publishes the stable compact message “Market data is unavailable.”

The compact error gains a Retry button that invokes the existing full retry action. Generation and task-cancellation checks guard every market result so wallet changes, view cancellation, or deletion cannot publish stale enrichment or errors.

## Risks / Trade-offs

- **[Market requests are repeated after each home portfolio load]** → Keep the behavior home-only and rely on the endpoint's server-side cached response instead of introducing a local schema.
- **[Provider values can represent different update times]** → Apply the approved deterministic per-field precedence and preserve the original provider payloads for future decisions.
- **[A portfolio event can render before enrichment completes]** → Keep the rows usable and the loading indicator visible; replace only price/change when enrichment arrives.
- **[Protocol expansion touches fixtures and test doubles]** → Add minimal success, failure, or scripted implementations without changing their existing portfolio behavior.

## Migration Plan

Add tests, extend the repository boundary, implement home orchestration and presentation recovery, then run the complete test suite. No data migration or cache invalidation is required. Rollback removes the repository method and home second stage; existing holdings and token-market domain models remain compatible.

## Open Questions

None. Product sequencing, provider precedence, retry policy, scope, persistence, loading, failure, recovery, and cancellation behavior were resolved during grilling.
