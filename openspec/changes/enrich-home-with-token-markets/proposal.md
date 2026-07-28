## Why

The selected-wallet home screen currently stops after loading holdings from `/v1/wallet/{address}`, so the token rows and wallet total remain without the provider-specific price and 24-hour-change data already exposed by `/v1/tokens/{address}`. The home load needs a resilient second stage that enriches usable holdings without making them dependent on market-data availability.

## What Changes

- After a selected-wallet portfolio load finishes successfully, fetch its token markets and enrich matching home token rows in memory.
- Prefer CoinGecko price and 24-hour change per field, fall back to CoinMarketCap, and preserve an existing portfolio field when neither provider supplies that field.
- Retry transient token-market failures twice with 0.5-second then 1-second backoff while keeping the token loading indicator visible.
- Preserve the loaded portfolio after market retries fail, show a compact “Market data is unavailable.” error with a retry action, and rerun the full portfolio-then-market sequence on retry or pull-to-refresh.
- Cancel the market request and backoff when the selected wallet load becomes obsolete.
- Leave native-token loading, wallet-list portfolio loading, and persistence unchanged.

## Capabilities

### New Capabilities

- `wallet-home-market-enrichment`: Defines selected-wallet sequencing, token matching and provider precedence, retry and cancellation behavior, loading state, and non-blocking market errors.

### Modified Capabilities

- `token-market-api`: Preserve independent provider values at the domain and remote boundary while allowing a downstream presentation feature to apply an explicit provider precedence without mutating those values.

## Impact

- Extends the token repository boundary so the home feature can request the existing token-market remote operation without adding storage.
- Updates `WalletHomeViewModel` orchestration and the compact home error presentation.
- Adds repository and home-view-model test coverage for market fetching, enrichment, retries, loading, errors, refresh, and cancellation.
