## 1. Test Coverage

- [x] 1.1 Add repository tests for three-attempt transient retry, exact backoff delays, fail-fast errors, cancellation, and absence of wallet-store writes.
- [x] 1.2 Add home-view-model tests for post-portfolio sequencing, one request after cached/fresh events, provider precedence, field preservation, unmatched tokens, loading, failure, recovery, refresh, and stale-result cancellation.

## 2. Repository Integration

- [x] 2.1 Extend `TokenRepositoryProtocol` and its production, fixture, failing, and test-double implementations with an uncached token-market operation.
- [x] 2.2 Implement transient error classification, three-attempt retry, cancellable 0.5-second/1-second backoff, and testable delay injection in `TokenRepository`.

## 3. Home Enrichment

- [x] 3.1 Sequence selected-wallet token markets after a successful portfolio stream while leaving native-token and wallet-list flows unchanged.
- [x] 3.2 Enrich matched holdings in memory with CoinGecko-first per-field fallback while preserving portfolio structure and unmatched tokens.
- [x] 3.3 Keep loading visible during market work, retain holdings on failure, suppress obsolete results, and expose the stable market error state.
- [x] 3.4 Add a Retry action to the compact token error presentation and route it through the full existing retry sequence.

## 4. Verification

- [x] 4.1 Run focused repository and home-view-model tests and resolve failures.
- [x] 4.2 Run the complete test/build suite, validate the OpenSpec change, and confirm only scoped files changed.
