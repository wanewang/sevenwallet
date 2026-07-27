# Token Market API

## Purpose

Define the domain models, decoding rules, identity, and remote-data-source behavior for token-market responses.

## Requirements

### Requirement: Token-market responses have independent domain models
The client SHALL represent the cached token-market response with `TokenMarketPortfolio`, `TokenMarket`, `CoinGeckoMarket`, and `CoinMarketCapMarket` domain values without changing the existing holdings models.

#### Scenario: Both providers return populated data
- **WHEN** `/v1/tokens/{address}` returns a valid portfolio whose token contains populated CoinGecko and CoinMarketCap objects
- **THEN** the client exposes the required portfolio and token values, each provider's documented ID type, exact decimal balances and prices, numeric 24-hour changes, and the parsed portfolio timestamp

#### Scenario: Existing holdings models remain independent
- **WHEN** token-market support is added
- **THEN** the existing `TokenPortfolio` and `WalletToken` contract remains unchanged

### Requirement: Only documented nullable values are optional
The client SHALL accept explicit null or omitted values for `tokenAddress`, `cg`, `cmc`, and each provider's `priceUSD` and `change24hPercent`, while requiring every other documented token-market property.

#### Scenario: Nullable values are null
- **WHEN** a valid token-market response explicitly sets every documented nullable property to null
- **THEN** decoding succeeds and the corresponding domain properties are `nil`

#### Scenario: Nullable values are omitted
- **WHEN** a valid token-market response omits one or more documented nullable properties
- **THEN** decoding succeeds and the corresponding domain properties are `nil`

#### Scenario: Structural value is absent or null
- **WHEN** a required portfolio, token, or provider property is absent or null
- **THEN** the token remote data source reports `APIError.invalidData`

### Requirement: Token-market wire values are strictly converted
The client MUST convert required token balances and optional provider USD-price strings to `Decimal`, provider 24-hour JSON numbers to `Decimal`, and the required portfolio fetched timestamp to `Date` using standard and fractional ISO 8601 support.

#### Scenario: Fractional timestamp and exact decimals are returned
- **WHEN** a response contains a fractional ISO 8601 portfolio timestamp and valid decimal strings and numbers
- **THEN** the client preserves the represented instant and exact decimal values

#### Scenario: Non-null converted value is malformed
- **WHEN** a balance, provider price, provider change, or portfolio timestamp has an invalid non-null wire value or type
- **THEN** the token remote data source reports `APIError.invalidData`

### Requirement: Market-token identity matches wallet-token identity
Every `TokenMarket` SHALL expose a key derived from its symbol and lowercased token address, using `native` when no token address exists, and its identifiable ID SHALL equal that key.

#### Scenario: Contract market token is identified
- **WHEN** a market token has a mixed-case contract address
- **THEN** its key and ID contain the symbol and lowercased contract address

#### Scenario: Native market token is identified
- **WHEN** a market token has no token address
- **THEN** its key and ID contain the symbol and `native`

### Requirement: Token-market endpoint is separately callable
The token remote data source SHALL fetch `/v1/tokens/{normalizedAddress}` independently from the existing holdings endpoint and SHALL validate that the response wallet matches the requested address.

#### Scenario: Token-market request succeeds
- **WHEN** a caller fetches token markets for a valid address and the response contains the same wallet
- **THEN** the client requests the normalized token-market path and returns the mapped market portfolio

#### Scenario: Response wallet differs
- **WHEN** the returned wallet does not equal the requested address after normalization
- **THEN** the token remote data source reports `APIError.invalidData`

### Requirement: Market providers remain independent
The client SHALL expose CoinGecko and CoinMarketCap data separately and SHALL NOT select or synthesize a preferred market price or change value.

#### Scenario: Providers disagree
- **WHEN** both providers return different USD prices or 24-hour changes
- **THEN** both original provider values remain independently available
