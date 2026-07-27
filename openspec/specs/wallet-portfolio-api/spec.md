# Wallet Portfolio API

## Purpose

Define the wallet holdings route, address normalization, response decoding, and behavior for unavailable market enrichment.

## Requirements

### Requirement: Wallet portfolio requests use the wallet route
The client SHALL request remote wallet holdings from `/v1/wallet/{address}` using the normalized wallet address and SHALL NOT request `/v1/addresses/{address}/tokens` as a fallback.

#### Scenario: Fetch a wallet portfolio
- **WHEN** the client fetches a portfolio for a valid mixed-case EVM address
- **THEN** it sends the request to `/v1/wallet/{normalized-address}`

#### Scenario: Wallet route fails
- **WHEN** the wallet route returns an error
- **THEN** the client reports the existing typed error without requesting the legacy holdings route

### Requirement: Wallet route preserves the holdings contract
The client SHALL decode a successful wallet-route response into the existing `TokenPortfolio` and `WalletToken` domain values using the existing address validation and exact numeric conversion rules.

#### Scenario: Valid wallet portfolio is returned
- **WHEN** `/v1/wallet/{address}` returns a valid `TokenPortfolio` response for the requested address
- **THEN** the client exposes the returned portfolio metadata, tokens, balances, prices, and token metadata through the existing domain contract

#### Scenario: Response belongs to another address
- **WHEN** the wallet route returns a portfolio whose address differs from the requested address
- **THEN** the client reports `APIError.invalidData`

### Requirement: Unavailable market enrichment remains optional
The client SHALL preserve `change24hPercent`, `marketCapUSD`, and `marketDataUpdatedAt` as optional wallet-token values when the wallet route returns them as null or omits them.

#### Scenario: Wallet route has no market enrichment
- **WHEN** a wallet-route token contains null or omitted market-enrichment fields
- **THEN** decoding succeeds and the corresponding wallet-token properties are `nil`

#### Scenario: Token row has no 24-hour change
- **WHEN** a decoded wallet token has no 24-hour change
- **THEN** its existing presentation displays the neutral `-` placeholder

### Requirement: Endpoint migration preserves cache policy
The client SHALL continue to use the existing portfolio cache and refresh policy without invalidating stored portfolios solely because the remote route changed.

#### Scenario: Existing portfolio cache is still fresh
- **WHEN** a previously stored portfolio satisfies the current freshness policy
- **THEN** the repository may return it without forcing a wallet-route request

#### Scenario: Portfolio refresh succeeds
- **WHEN** a wallet-route response is refreshed and saved
- **THEN** it replaces the requested wallet's cached portfolio through the existing persistence behavior
