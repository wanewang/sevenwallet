## ADDED Requirements

### Requirement: Selected-wallet home loads markets after holdings
The selected-wallet home SHALL request token markets once after its portfolio stream finishes successfully with at least one holding to enrich, and SHALL NOT request markets for native-token or wallet-list portfolio loads.

#### Scenario: Portfolio holds no tokens
- **WHEN** a selected-wallet portfolio stream finishes successfully with an empty holdings list
- **THEN** the home does not request token markets and publishes no market error

#### Scenario: Cached and fresh portfolio precede one market request
- **WHEN** a selected-wallet portfolio load emits cached holdings, refreshes, emits fresh holdings, and finishes
- **THEN** the home shows the holdings events and requests token markets once after the stream finishes

#### Scenario: Cached-only portfolio precedes one market request
- **WHEN** a selected-wallet portfolio load emits a cache hit that does not require a holdings refresh and finishes
- **THEN** the home requests token markets once after the cached portfolio stream finishes

#### Scenario: Portfolio load fails
- **WHEN** the selected-wallet portfolio stream fails
- **THEN** the home preserves its existing portfolio error behavior and does not request token markets

#### Scenario: Non-home portfolio consumers load
- **WHEN** native tokens or wallet-list portfolio summaries load
- **THEN** those flows do not request token markets and retain their existing behavior

### Requirement: Home market data enriches matching portfolio tokens
The home SHALL match market tokens to portfolio tokens by the shared symbol and normalized token-address/native key, preserve the portfolio's token membership, order, identity, balance, metadata, and logo, and change only supported market presentation fields.

The provider that supplies a matched token's 24-hour change SHALL also supply its price, so both displayed fields describe the same provider snapshot. CoinGecko SHALL lead unless only CoinMarketCap supplies a 24-hour change. When the leading provider omits a price, the home SHALL use the other provider's price before falling back to the portfolio value.

#### Scenario: Both providers populate a matched token
- **WHEN** a matched market token has non-null CoinGecko and CoinMarketCap price and 24-hour-change values
- **THEN** the home uses the CoinGecko price and change while preserving every non-market portfolio field

#### Scenario: Only CoinMarketCap supplies a 24-hour change
- **WHEN** CoinGecko omits a matched token's 24-hour change and CoinMarketCap supplies both a change and a price
- **THEN** the home uses the CoinMarketCap change and the CoinMarketCap price, discarding the CoinGecko price

#### Scenario: The leading provider omits a price
- **WHEN** CoinMarketCap supplies a matched token's 24-hour change but omits its price while CoinGecko supplies a price
- **THEN** the home uses the CoinMarketCap change with the CoinGecko price

#### Scenario: Neither provider supplies a 24-hour change
- **WHEN** both providers omit a matched token's 24-hour change
- **THEN** the home preserves the portfolio's 24-hour change and uses the CoinGecko price before the CoinMarketCap price

#### Scenario: Both providers omit one field
- **WHEN** both providers omit a price or 24-hour change for a matched token
- **THEN** the home preserves that field's existing portfolio value

#### Scenario: Responses contain unmatched tokens
- **WHEN** a token occurs in only the portfolio or only the market response
- **THEN** the portfolio-only token remains unchanged and the market-only token is not added to the home

### Requirement: Token-market requests use bounded transient retries
The token repository SHALL make one initial market request and at most two retries, waiting 0.5 seconds and then 1 second, and SHALL retry only transport errors, non-HTTP responses, HTTP 408, HTTP 429, and HTTP 5xx responses.

The repository SHALL run at most one attempt chain per address at a time, joining a concurrent caller to the in-flight chain instead of starting a second one. It SHALL reject a market request for a suspended address without contacting the remote, and suspending an address SHALL cancel that address's in-flight attempt chain rather than letting its remaining retries run.

#### Scenario: Concurrent callers request the same address
- **WHEN** a second market request for an address starts while the first is still in flight
- **THEN** both callers receive the first chain's result and the remote is contacted once

#### Scenario: Address is already suspended
- **WHEN** a market request starts for an address whose portfolio loads are suspended
- **THEN** the repository reports cancellation immediately without contacting the remote or waiting a retry delay

#### Scenario: Address is suspended mid-flight
- **WHEN** an address is suspended while its market attempt chain is waiting to retry
- **THEN** the chain stops without a further attempt and the caller observes cancellation

#### Scenario: Transient failures recover
- **WHEN** the first two market attempts fail transiently and the third succeeds
- **THEN** the repository waits for the two specified delays and returns the third response after exactly three attempts

#### Scenario: Transient failures are exhausted
- **WHEN** all three market attempts fail transiently
- **THEN** the repository returns the final failure without a fourth attempt

#### Scenario: Failure is not retryable
- **WHEN** a market request fails with invalid request data, an invalid response payload, another HTTP 4xx status, or a non-API error
- **THEN** the repository returns that failure immediately without waiting or retrying

#### Scenario: Market loading is cancelled
- **WHEN** cancellation occurs during a market attempt or retry delay
- **THEN** the repository stops without another attempt and the obsolete home load publishes no enrichment or error

### Requirement: Market loading and failure remain visible and recoverable
The home SHALL show its token loading indicator while a market request or retry delay is active, and an exhausted market failure SHALL retain the loaded portfolio while showing the compact message “Market data is unavailable.” with a Retry action.

#### Scenario: Market enrichment is in progress
- **WHEN** the portfolio has loaded and a market attempt or retry delay is active
- **THEN** the portfolio tokens remain visible and the token loading indicator remains visible

#### Scenario: Market enrichment succeeds
- **WHEN** a market request succeeds
- **THEN** the home publishes enriched rows, clears the market error, and hides the loading indicator

#### Scenario: Market enrichment fails finally
- **WHEN** a non-retryable market failure occurs or transient retries are exhausted
- **THEN** the home keeps the portfolio rows, hides the loading indicator, and shows “Market data is unavailable.” with Retry

#### Scenario: User retries market failure
- **WHEN** the user activates Retry after a market failure
- **THEN** the home reruns the portfolio stage followed by the bounded market stage

#### Scenario: User pulls to refresh
- **WHEN** the user pulls to refresh a selected wallet
- **THEN** the home requests the portfolio with its existing pull-refresh policy and then runs the bounded market stage

### Requirement: Home enrichment remains in memory
The client SHALL NOT persist the token-market response or enriched home values as part of this capability.

#### Scenario: Market enrichment succeeds
- **WHEN** the home applies token-market values to its displayed portfolio
- **THEN** no token-market or enriched portfolio value is written to the wallet store
