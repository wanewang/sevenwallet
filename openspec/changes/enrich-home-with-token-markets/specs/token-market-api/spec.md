## MODIFIED Requirements

### Requirement: Market providers remain independent
The token-market domain and remote data source SHALL expose CoinGecko and CoinMarketCap data separately and SHALL NOT select, average, or mutate a preferred market price or change value. A presentation consumer that needs one value SHALL apply its specified precedence without removing or changing either provider value in the token-market response.

#### Scenario: Providers disagree at the domain boundary
- **WHEN** both providers return different USD prices or 24-hour changes
- **THEN** both original provider values remain independently available

#### Scenario: Home presentation needs one value
- **WHEN** the selected-wallet home enriches a matched holding from provider-specific market values
- **THEN** it applies the home capability's explicit precedence while the source token-market portfolio retains both original provider values
