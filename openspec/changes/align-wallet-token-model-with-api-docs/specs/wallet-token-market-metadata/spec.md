## ADDED Requirements

### Requirement: Documented token market metadata is represented
The client SHALL represent `change24hPercent`, `coinKey`, `marketCapUSD`, and `marketDataUpdatedAt` as optional properties on each decoded wallet token, using decimal values for numeric market data and a date value for the timestamp.

#### Scenario: Response contains all market metadata
- **WHEN** a native-token or portfolio response contains valid non-null values for all four documented market-metadata properties
- **THEN** the decoded wallet token exposes the same coin key and exact decimal values and exposes the parsed market-data timestamp

#### Scenario: Response contains null market metadata
- **WHEN** a token response contains explicit `null` values for the documented nullable market-metadata properties
- **THEN** decoding succeeds and the corresponding wallet-token properties are `nil`

#### Scenario: Response omits market metadata
- **WHEN** a token response omits one or more documented nullable market-metadata properties
- **THEN** decoding succeeds and each omitted property is `nil`

### Requirement: Market metadata follows documented wire types
The client MUST decode `change24hPercent` and `marketCapUSD` from JSON numbers and MUST decode `marketDataUpdatedAt` from a valid ISO 8601 string using the API's existing standard and fractional-second date support.

#### Scenario: Fractional market timestamp is returned
- **WHEN** `marketDataUpdatedAt` contains a valid ISO 8601 timestamp with fractional seconds
- **THEN** the client preserves the represented instant in the wallet-token date value

#### Scenario: Market metadata has an invalid shape
- **WHEN** a non-null numeric market field uses a non-numeric JSON type or `marketDataUpdatedAt` is not a supported ISO 8601 timestamp
- **THEN** the token remote data source reports invalid response data

### Requirement: Token key uses symbol and address
Every wallet token SHALL expose a matching key derived from its symbol and its lowercased token address, using a native marker when no token address exists, and its identifiable ID SHALL equal that key.

#### Scenario: Contract token key is derived
- **WHEN** a token has symbol `USDC` and a mixed-case contract address
- **THEN** its key and ID contain `USDC` and the lowercased contract address

#### Scenario: Native token key is derived
- **WHEN** a token has symbol `ETH` and no token address
- **THEN** its key and ID equal `ETH:native`

#### Scenario: Coin key changes independently
- **WHEN** otherwise identical tokens have different or absent `coinKey` values
- **THEN** they have the same symbol/address matching key

### Requirement: Token metadata and wallet balances are cached separately
The cache SHALL store token metadata once by token matching key without raw or decimal balances, and SHALL store each wallet balance with its normalized wallet address, token matching key, raw balance, decimal balance, and portfolio position.

#### Scenario: Shared token is saved for two wallets
- **WHEN** two wallet portfolios contain the same token key with different balances
- **THEN** one shared token-metadata value can serve both wallets while each wallet retains its own balance

#### Scenario: Metadata includes market enrichment
- **WHEN** a token with documented market metadata is cached
- **THEN** its metadata record preserves that enrichment without storing wallet-specific balance values

### Requirement: Cached wallet tokens are composed by matching key
The cache SHALL load balance records only for the requested wallet, order them by their saved portfolio positions, match each token key to shared metadata, and compose complete `WalletToken` values.

#### Scenario: Requested wallet is composed
- **WHEN** a cached portfolio is loaded for a wallet with matching metadata and balance records
- **THEN** the returned wallet tokens combine shared metadata with only that wallet's balances in the original API order

#### Scenario: Native snapshot is composed
- **WHEN** a valid cached native-token snapshot is loaded
- **THEN** its ordered metadata keys are composed as wallet tokens with zero raw and decimal balances

#### Scenario: Matching metadata is missing
- **WHEN** a cached snapshot references a token key with no valid metadata record
- **THEN** the affected snapshot is invalidated and the load returns a cache miss rather than a partial result

### Requirement: Wallet cache replacement and purge preserve isolation
Saving a portfolio SHALL replace the prior balance set for that wallet atomically, and purging a wallet SHALL remove its portfolio, transactions, and balances without removing shared token metadata, the native snapshot, or other wallets' balances.

#### Scenario: Portfolio snapshot is replaced
- **WHEN** a wallet portfolio is saved again with a changed token set or balances
- **THEN** loading that wallet returns only the replacement balance set and current portfolio metadata

#### Scenario: One wallet is purged
- **WHEN** cached address data is purged for one wallet
- **THEN** that wallet's portfolio, transaction pages, and balance records are absent while another wallet and shared token metadata remain loadable

#### Scenario: Legacy snapshot is encountered
- **WHEN** a native or portfolio snapshot payload does not use the supported normalized-cache version
- **THEN** the store discards the affected snapshot and returns a cache miss so remote data can repopulate it
