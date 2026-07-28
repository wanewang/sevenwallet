## ADDED Requirements

### Requirement: Selected-wallet home loads markets after holdings
The selected-wallet home SHALL request token markets once after its portfolio stream finishes successfully with at least one portfolio value, and SHALL NOT request markets for native-token or wallet-list portfolio loads.

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

#### Scenario: Both providers populate a matched token
- **WHEN** a matched market token has non-null CoinGecko and CoinMarketCap price and 24-hour-change values
- **THEN** the home uses the CoinGecko price and change while preserving every non-market portfolio field

#### Scenario: CoinGecko omits one field
- **WHEN** CoinGecko omits a price or 24-hour change that CoinMarketCap supplies for a matched token
- **THEN** the home uses CoinMarketCap for that missing field independently of the other field

#### Scenario: Both providers omit one field
- **WHEN** both providers omit a price or 24-hour change for a matched token
- **THEN** the home preserves that field's existing portfolio value

#### Scenario: Responses contain unmatched tokens
- **WHEN** a token occurs in only the portfolio or only the market response
- **THEN** the portfolio-only token remains unchanged and the market-only token is not added to the home

### Requirement: Token-market requests use bounded transient retries
The token repository SHALL make one initial market request and at most two retries, waiting 0.5 seconds and then 1 second, and SHALL retry only transport errors, non-HTTP responses, HTTP 408, HTTP 429, and HTTP 5xx responses.

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
