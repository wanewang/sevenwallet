## Context

The client currently loads wallet holdings from `/v1/addresses/{address}/tokens` into `TokenPortfolio` and `WalletToken`. The latest Swagger definition also exposes `/v1/tokens/{address}`, a read-only view over cached holdings with provider-specific CoinGecko and CoinMarketCap enrichment. Its response uses different portfolio field names and token shapes, and it intentionally does not refresh holdings from Alchemy.

This change represents that contract independently. Existing holdings, repository, cache, and presentation behavior must remain unchanged.

## Goals / Non-Goals

**Goals:**

- Represent every field in `TokenMarketPortfolio`, `TokenMarket`, `CoinGeckoMarket`, and `CoinMarketCapMarket` with value-semantic Swift types.
- Expose a separately callable token-market endpoint through `TokenRemoteDataSource`.
- Preserve exact decimal values and parse the required portfolio timestamp using the client's existing standard and fractional ISO 8601 support.
- Accept null or omitted values only for properties marked nullable by Swagger.
- Give market tokens a deterministic key compatible with existing wallet-token identity.

**Non-Goals:**

- Replacing or changing the existing portfolio endpoint and models.
- Selecting a preferred market-data provider or merging provider values into `WalletToken`.
- Adding repository behavior, caching, persistence models, or UI consumption.
- Changing transaction or native-token behavior.

## Decisions

1. **Add independent domain types.** `TokenMarketPortfolio` will contain a validated `EVMAddress` wallet, required network and fetched date, and market tokens. `TokenMarket` will contain the required identity, precision, and decimal balance plus optional provider values. Provider-specific domain types retain their different documented ID types: `String` for CoinGecko and `Int` for CoinMarketCap. Reusing `WalletToken` was rejected because the market route omits required holdings fields and has two independent provider payloads.

2. **Keep wire names inside private DTOs.** Transport DTOs will mirror `wallet`, `portfolioFetchedAt`, `cg`, `cmc`, and `priceUSD`; the mapper will expose descriptive `coinGecko` and `coinMarketCap` domain properties. This prevents abbreviated wire names from leaking into downstream Swift code.

3. **Use strict value conversion.** Required `balance` and optional provider `priceUSD` strings will be parsed as `Decimal`; numeric provider changes will decode directly as optional `Decimal`; and `portfolioFetchedAt` will become a required `Date`. Explicit null and omission are accepted only by optional DTO properties. Invalid non-null wire types, malformed decimal strings, malformed timestamps, missing structural fields, and a returned wallet different from the requested address all produce `APIError.invalidData`.

4. **Share token matching semantics.** `TokenMarket.key` will combine its symbol with the lowercased token address, using `native` when the nullable address is absent, and `id` will equal that key. Provider IDs do not participate in identity, allowing the new market data to be joined to `WalletToken` later without defining that integration now.

5. **Preserve providers independently.** No combined price, change, or provider-precedence helper will be added because the API contract does not specify which source wins when both exist or disagree.

6. **Extend only the remote boundary.** `APIEndpoint` will gain a token-market case at `/v1/tokens/{address}`, and `TokenRemoteDataSourceProtocol`/`TokenRemoteDataSource` will gain `fetchTokenMarkets(address:)`. No repository protocol will change until product behavior requires consuming the new response.

## Risks / Trade-offs

- **[Risk] The strict structural model rejects a partially populated server response** → This matches the agreed contract that only Swagger-marked nullable fields may be absent or null and prevents unusable values from entering the domain.
- **[Risk] Provider values can disagree without a convenient selected price** → Preserve both sources faithfully and defer precedence to a future product requirement.
- **[Risk] The new callable method is not yet used by application flows** → Keep this change focused on contract alignment while making later integration possible without redesigning the transport layer.
- **[Risk] Provider DTO and domain types add parallel model shapes** → Keep DTOs private and mapping explicit; do not generalize the two providers because their identity types differ.

## Migration Plan

Add tests first, then add the new domain types, endpoint, DTO mapping, and remote method. Existing stored data and application behavior require no migration. Rollback consists of removing the additive endpoint, models, method, and tests.

## Open Questions

None. Provider selection and application integration are intentionally deferred.
