# Network Repository and Empty Wallet Design

## Goal

Replace the app's hardcoded token sample data with the wallet API, add a SwiftData-backed repository layer for every token and address endpoint, and present the approved empty-wallet card while no wallet has been imported.

The implementation must keep network and persistence details out of SwiftUI views, show cached data immediately, limit automatic refreshes to data older than 30 minutes, and allow a deliberate third pull-to-refresh within one minute to force a network request.

## API Contract

The service documents a `/v1` base path and three operations:

| Operation | Purpose |
| --- | --- |
| `GET /v1/native` | Native token metadata and current USD price. |
| `GET /v1/addresses/{address}/tokens` | Native and ERC-20 portfolio for an EVM address. |
| `GET /v1/addresses/{address}/transactions?limit={limit}&pageKey={pageKey}` | Paginated asset transfers for an EVM address. |

The address token and transaction operations are implemented and tested at the data and repository layers in this iteration. They do not receive screens yet. The current home screen consumes only `/v1/native`; importing and saving a wallet address is a separate follow-up feature.

## Scope

This iteration includes:

- Runtime API configuration with no committed service URL.
- URLSession request and response handling for all three operations.
- API response models and domain models for tokens, prices, portfolios, transaction pages, and transfers.
- SwiftData persistence for native tokens, address portfolios, transaction pages, and their successful-fetch timestamps.
- Feature-specific token and transaction repositories.
- Cache-first delivery followed by a network refresh when required.
- A 30-minute freshness threshold and a third-pull force-refresh rule.
- Replacement of launch sample tokens with `/v1/native` data.
- Loading and error states for the Tokens section.
- The approved empty-wallet card and a matching expanded populated-wallet card size.
- Unit, repository integration, view-model, UI, and simulator verification.

This iteration excludes:

- Address-entry UI.
- Saving or selecting imported wallets.
- Navigation from the empty-wallet card.
- Portfolio or transaction-history screens.
- Adding Fastlane itself. The configuration is compatible with a later Fastlane archive workflow.

## Architecture

Use four layers with one-way dependencies toward the domain layer.

### API client

`APIClient` uses an injected `URLSession` and base URL. It constructs relative endpoint paths, adds query items, validates HTTP responses, decodes success payloads, and decodes the API's `{ "error": string }` failure payload when present.

The client distinguishes transport errors, non-success HTTP responses, and invalid response data. It has no cache or SwiftUI responsibilities.

### Remote data sources

The token remote data source exposes native-token and address-portfolio operations. The transaction remote data source exposes the paginated transaction operation. These types translate API payloads into domain values and keep wire-format decisions out of repositories and view models.

### SwiftData store

A SwiftData-backed store persists endpoint snapshots and performs database work away from the main actor. Stored records are persistence-specific and do not leak `@Model` types into the UI.

The store supports:

- One native-token snapshot.
- One portfolio snapshot per normalized address.
- One transaction snapshot per normalized address, requested limit, and incoming page key.
- Atomic replacement of a successfully refreshed snapshot.
- Successful-fetch timestamps recorded from an injected clock.

The API's portfolio `fetchedAt` value remains response metadata. Cache freshness uses the local timestamp recorded only after decoding and persistence both succeed.

### Repositories

`TokenRepository` owns native-token and address-portfolio loading. `TransactionRepository` owns transaction-page loading. Both coordinate remote and SwiftData data sources and are the only layer that decides whether a network request is needed.

Repository interfaces return cache-first asynchronous streams of load events. A stream can publish `.cached(value)`, `.refreshing`, and `.fresh(value)` in that order when all three phases apply. It throws a typed repository error after `.refreshing` when refresh fails. This lets view models render the database result immediately and drive network-only loading UI without accessing either data source directly.

Requests for the same resource key are coalesced. Concurrent callers share one in-flight network operation rather than issuing duplicates.

## Runtime Configuration

The production service URL is never hardcoded and no real URL value is committed.

`BASE_URL` resolves in this order:

1. `ProcessInfo.processInfo.environment["BASE_URL"]` for an Xcode launch using a local, unshared scheme value.
2. `Bundle.main`'s generated `BASE_URL` Info.plist entry for an archived build.
3. A typed configuration error when neither source contains a valid absolute HTTP or HTTPS URL.

The project may commit build-setting wiring that maps the generated Info.plist key to `$(BASE_URL)`, because that contains no environment-specific value. A future Fastlane lane can read `BASE_URL` from its process environment or CI secret store and pass it as an Xcode build setting during Archive. The built app then reads the expanded Info.plist value at runtime.

`BASE_URL` is the service origin, without the `/v1` API path. A trailing slash is accepted and normalized. The client appends the documented `/v1` paths and rejects configuration values with unsupported schemes, query items, or fragments.

Tests inject configuration and do not depend on a developer's scheme.

## Domain Data

Token domain data represents:

- Optional token address, because `/v1/native` returns `null` for native assets.
- Symbol, name, decimals, native status, optional logo URL, and coin key.
- Raw balance as an unmodified string.
- Display balance and USD prices as `Decimal` values parsed from API strings.
- Optional price currency and last-updated timestamp.

Using `Decimal` avoids binary floating-point errors in financial calculations and formatting. Missing optional metadata does not fail the entire payload. Required identity or numeric fields that cannot be decoded produce an invalid-response error instead of silently inventing values.

A portfolio contains its normalized address, network, API fetch metadata, and tokens. A transaction page contains its normalized address, optional next-page key, and transfers. Transfer fields mirror the documented asset, block number, category, sender, hash, recipient, and value fields.

An EVM address value validates a `0x` prefix followed by exactly 40 hexadecimal characters. Its normalized cache and request identity is lowercase.

## Cache and Refresh Policy

Every repository load follows this sequence:

1. Read the snapshot for the requested resource key from SwiftData.
2. Publish cached data immediately when it exists.
3. Compare the local successful-fetch timestamp with the injected clock.
4. Contact the API when the snapshot is missing, its age is greater than 30 minutes, or the caller explicitly forces a refresh.
5. Decode the complete response and atomically replace its SwiftData snapshot.
6. Record the new successful-fetch timestamp.
7. Publish the fresh domain data.

A snapshot exactly 30 minutes old remains fresh; it becomes expired only when its age is greater than 30 minutes.

If a refresh fails, the repository does not replace the snapshot or advance its timestamp. A caller that already received cached data keeps that data and also receives the refresh error. With no cache, the load produces only the error.

### Pull-to-refresh override

The home view model records pull timestamps in a rolling 60-second window using an injected clock.

- The first and second pulls use the normal repository policy. They refresh only when data is missing or expired.
- The third pull inside the rolling window uses a forced policy, bypassing the 30-minute threshold.
- Issuing that forced refresh clears the retained pull timestamps, whether the request succeeds or fails.
- Pulls older than 60 seconds are removed before the count is evaluated.
- If the same resource already has an in-flight request, the forced caller joins it rather than creating a duplicate.

The counter is session state and is not persisted across app launches.

## Application Data Flow

The app creates its configuration, SwiftData model container, data sources, repositories, and `WalletHomeViewModel` at composition root startup. Views receive the prepared view model; they do not construct production repositories themselves.

On home-screen appearance:

1. The view model begins the native-token repository stream.
2. `isLoadingTokens` becomes true while a network operation is active.
3. Cached native tokens, when available, populate the rows immediately.
4. A missing or expired snapshot triggers `/v1/native`.
5. Fresh rows replace cached rows after persistence succeeds.
6. Network activity ends and the loading indicator stops.

The loading flag represents network activity, not a brief SwiftData read. A forced or expired-cache refresh leaves current rows visible while showing network activity.

## Home-Screen Design

### Empty-wallet card

Because wallet import is not part of this iteration, the application starts in a no-wallet state and replaces the populated wallet card with the approved empty state.

The card contains one vertical layout:

1. `SEVEN WALLET` aligned to the upper left with wide letter spacing.
2. A centered circular plus icon with a blue border and soft blue border glow.
3. Centered `Add your first wallet` primary text.
4. Centered `Import an address to start tracking` secondary text.

It uses the themed glass fill, a subtle dashed rounded border, and responsive light/dark colors. It is visual-only for this request and does not expose a control that appears actionable but performs no work.

The empty and populated wallet cards share a 208-point minimum height, matching the logical height of the supplied 2x reference at the current page width. The populated `WalletCardView` expands to that size so switching wallet state later will not shift the Tokens section. Both may grow beyond the minimum when accessibility text sizes require it.

### Tokens section

The Tokens section preserves its existing title, Manage control, grouped rows, and pinned-header behavior.

A small `ProgressView` appears immediately to the right of the `Tokens` title while a native-token network request is in progress. The Manage control remains trailing. Cached rows remain visible beneath the indicator during refresh.

Native-token rows use API data instead of samples:

- Remote `logoURI` image when available, with a symbol-based fallback.
- Token symbol and name.
- Current USD market price on the right.
- `-` for daily change because `/v1/native` does not provide that field.

Pull-to-refresh calls the view model's refresh coordinator and follows the cache and force-refresh policy above.

### Error presentation

If native-token loading fails with no cached rows, the Tokens section shows a concise inline error and Retry control. The empty-wallet card and theme control remain usable.

If a refresh fails while cached rows are visible, those rows remain in place and the section shows a brief inline refresh error. The network indicator stops. Retry uses the normal cache policy; the third-pull rule remains the explicit way to bypass a still-fresh cache.

## Error Model

The data layer distinguishes:

- Missing or invalid `BASE_URL`.
- Invalid EVM address.
- Transport failure.
- Non-success HTTP response with status and optional server message.
- Invalid or incomplete response data.
- SwiftData read or write failure.

Errors remain typed through the repository boundary. The home view model maps them to user-facing token-section state without exposing raw transport or database implementation details.

## Verification

### Configuration and API client tests

- Process environment takes precedence over the generated Info.plist value.
- The Info.plist value is used when the process environment is absent.
- Missing and invalid values produce configuration errors.
- Every endpoint builds the expected `/v1` path.
- Transaction `limit` and optional `pageKey` are encoded as query items.
- Success, API error payloads, transport failures, and malformed data are classified correctly.
- Decoding accepts documented nullable fields and the observed null native `tokenAddress`.

### Persistence and repository tests

- API string balances and prices become exact `Decimal` values.
- Native, per-address portfolio, and per-page transaction cache keys remain independent.
- A cache miss calls the network, stores the snapshot, and publishes fresh data.
- Fresh cache publishes without a network call.
- Expired cache publishes immediately and then publishes refreshed data.
- Cache age of exactly 30 minutes remains fresh; an age greater than 30 minutes expires.
- A failed refresh preserves cached data and its original timestamp.
- Concurrent loads for one resource produce one network request.
- Transaction pages preserve `nextPageKey` and round-trip through SwiftData.
- Invalid EVM addresses fail before a request is sent.

### Refresh coordinator and view-model tests

- Pulls outside the rolling window do not accumulate.
- The first two pulls inside 60 seconds use normal policy.
- The third pull forces refresh and resets the counter.
- The forced request joins an existing matching request.
- Home startup consumes the native-token repository.
- The loading indicator state matches network activity.
- Cached rows remain present through a failed background refresh.
- Native rows show market price and `-` daily change.

### UI and build verification

- The no-wallet launch shows all four approved empty-card texts and symbols.
- Empty and populated fixtures use the shared expanded card sizing contract.
- The Tokens header retains Manage and shows its progress indicator during an injected delayed refresh.
- Initial and cached-refresh errors use their correct presentations.
- Existing theme and pinned-header behavior remain functional.
- UI tests use deterministic injected repositories rather than the live service.
- The complete unit and UI test suites pass on an iOS simulator.
- The application builds for an iOS simulator with code signing disabled.

## Completion Criteria

The request is complete when all three documented API operations are available through the approved repositories, SwiftData cache and refresh behavior passes deterministic tests, the home screen loads `/v1/native` through the repository, the loading/error states work, the empty and populated wallet cards share the expanded size, no real `BASE_URL` value is committed, and the full simulator verification succeeds.
