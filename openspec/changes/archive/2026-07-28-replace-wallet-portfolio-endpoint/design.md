## Context

Wallet portfolio loads currently map `APIEndpoint.portfolio` to `/v1/addresses/{address}/tokens`. The deployed API exposes `/v1/wallet/{address}` with the same `TokenPortfolio` response schema, but it applies the new LI.FI/Moralis token-validation behavior and does not apply CoinGecko market enrichment. Consequently, `change24hPercent`, `marketCapUSD`, and `marketDataUpdatedAt` are null on the new route.

The existing client already normalizes `EVMAddress` values, decodes the shared response schema, represents those market fields as optional, renders a missing 24-hour change as `-`, and replaces cached token metadata after a successful refresh.

## Goals / Non-Goals

**Goals:**

- Route every remote wallet portfolio refresh through `/v1/wallet/{address}`.
- Preserve address normalization, decoding, repository, cache, and UI behavior.
- Prove the new request path with focused API-client coverage and the existing unit suite.

**Non-Goals:**

- Falling back to the legacy holdings route.
- Loading 24-hour changes or other market enrichment from the token-market route.
- Invalidating existing portfolio or native-token caches.
- Changing domain models, persistence schemas, refresh policy, or token-row layout.

## Decisions

### Replace the existing portfolio endpoint mapping

Keep the semantic `APIEndpoint.portfolio` case and change only its path to `/v1/wallet/{address}`. The data source, repository, and callers operate on a wallet portfolio rather than on a route name, so introducing a parallel endpoint case or data-source method would add unused surface area.

Alternative considered: add a new wallet endpoint alongside the legacy portfolio endpoint. Rejected because the legacy route must be replaced entirely and retaining it would permit accidental future use.

### Reuse the existing response decoder and domain models

Continue decoding `PortfolioDTO` into `TokenPortfolio` and `WalletToken`. The deployed operations reference the same response definition, and the existing optional market properties already accept null or omitted values.

Alternative considered: create a new wallet response model without 24-hour change. Rejected because it would duplicate the same holdings contract and make the planned market-data composition harder without improving validation.

### Do not add fallback or cache migration behavior

Propagate new-route failures through the existing error path without retrying the legacy route. Preserve the current 30-minute cache policy and allow normal refresh to replace any metadata previously returned by the old route.

Alternative considered: invalidate cached portfolios on upgrade. Rejected because the cache format remains valid, the shared cache version also covers unrelated native-token data, and the only transient difference is cosmetic market metadata.

## Risks / Trade-offs

- [A fresh pre-upgrade cache can temporarily show old 24-hour values] → Accept the bounded interval; normal expiry or a forced refresh replaces them.
- [The new server-side validation can return a different token set] → Treat this as the intended behavior of the new endpoint and preserve existing atomic portfolio replacement.
- [The new route fails after deployment] → Surface the existing typed error while retaining any cached portfolio; do not conceal the deployment issue with legacy fallback.

## Migration Plan

1. Change the portfolio endpoint mapping and its normalized request assertion.
2. Run focused API-client tests and the full unit-test target.
3. Ship without cache invalidation; existing cache policy governs the transition.

Rollback requires reverting the endpoint mapping and request assertion to the legacy route.

## Open Questions

None.
