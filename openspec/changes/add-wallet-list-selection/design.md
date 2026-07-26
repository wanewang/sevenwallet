## Context

`WalletSelectorView` already lists saved wallets and can select or add them, but its “Wallet details” action has no callback. `WalletRootView` owns the navigation path and routes add/edit destinations, while `WalletSession` owns the persisted saved-wallet snapshot and selection. Portfolio values are loaded cache-first through `TokenRepositoryProtocol`, but that repository is currently retained only by `WalletHomeViewModel` for the selected wallet.

The supplied `WalletDetailView` is a visual/interaction reference rather than code that can be copied directly: it uses model types and route cases that differ from this project. The new page must adapt that layout to `SavedWallet`, `WalletSession`, the existing theme, and the existing Add Wallet header style.

## Goals / Non-Goals

**Goals:**

- Make the selector’s full-list action functional and visually identify it as navigation.
- Present every saved wallet in the supplied card-list style, including portfolio summary and active state.
- Reuse the current wallet-selection persistence and add-wallet flow.
- Keep wallet identities visible while portfolio summaries load cache-first and refresh independently.
- Preserve testability by separating portfolio loading/formatting state from the SwiftUI layout.

**Non-Goals:**

- Changing the saved-wallet or portfolio persistence schemas.
- Adding wallet reordering, deletion, editing, search, or support for networks other than Ethereum.
- Replacing the compact selector or changing its direct wallet-selection behavior.
- Introducing a new remote endpoint or third-party dependency.

## Decisions

### Add a dedicated navigation destination

Add a wallet-list case to `Screen`. `WalletHomeView` will expose an `onShowWalletList` callback to `WalletSelectorView`; choosing “Wallet list” dismisses the overlay before `WalletRootView` appends the new destination. This follows the existing root-owned navigation pattern and prevents the selector from owning navigation state.

The alternative was to present the list as a sheet or to let the selector mutate a shared path. A pushed destination better matches the supplied full-screen back-button design and keeps navigation ownership in one place.

### Reuse the token repository through dependency injection

Carry the shared `TokenRepositoryProtocol` on `WalletAppState` alongside the existing session and home view model. `AppDependencies.makeAppState` already builds that repository, so the new field is populated at its three construction sites — the live path, `fixtureState`, and `unavailableState` — and `WalletRootView` hands it to the wallet-list feature. A new `WalletListViewModel` will consume `portfolio(address:policy:)` with `.ifExpired` for each saved wallet and retain row state keyed by wallet ID.

Reusing the repository preserves its cache-first/fresh event semantics and per-address request coalescing. Fetching through `WalletHomeViewModel` was rejected because that model represents only the selected wallet and would couple two screens. Reading SwiftData cache records directly was rejected because it would bypass repository freshness and error behavior.

### Load portfolio summaries independently

The list view model will create child tasks for wallet addresses so one slow or failed portfolio does not block the other rows. Each row begins with saved-wallet identity data, shows a loading placeholder until its first portfolio arrives, then derives:

- total value from the sum of token balance multiplied by available USD price;
- asset count from the portfolio token count;
- network text as “Ethereum”, consistent with the app’s only supported network.

Cached values remain visible while a refresh is in progress or if a later refresh fails. Rows with no usable value show unavailable placeholders, and the page exposes a retry action for failed loads. Tasks are cancelled when the page disappears or the wallet set changes.

A single sequential load was considered, but it would make later rows wait unnecessarily. A new aggregate API was also considered and rejected because none exists and it is outside this UI change.

### Keep selection authoritative in `WalletSession`

Tapping a row calls `WalletSession.select(id:)`. The list returns to wallet home only after the call succeeds (including the existing no-op success for the already active wallet). On failure, the page remains visible and presents the session’s recoverable selection error. Active styling always derives from `selectedWalletID`, so the badge and accent border cannot drift from persisted selection.

`WalletHomeView` already renders the same `selectionErrorMessage`, so the list owns the message while it is open: a new `WalletSession.clearSelectionError()` resets the `private(set)` property, and `WalletRootView` calls it when the wallet-list destination is popped. Home therefore never repeats a failure the user already saw and left behind. Suppressing the message on home only while the list is pushed was rejected because the error would reappear on back, and giving the list its own error state was rejected because it would create a second source of truth for one failure.

### Match existing visual components and semantics

`WalletListView` will use the app theme and the `WalletFormView` header measurements: a 44-point circular back control, bold title, matching horizontal/top padding, and hidden system navigation bar. The title is “Wallets”; an accent-styled trailing plus button opens the existing add destination. Rows use the supplied rounded-card composition, wallet color gradient, monospaced address/value text, active capsule, and active accent outline. Controls and wallet rows receive stable accessibility labels, identifiers, and selected traits.

## Risks / Trade-offs

- [Opening the list can fan out one refresh per saved wallet] → Use `.ifExpired`, display cache first, reuse repository coalescing, cancel work off-screen, and keep failures isolated per row.
- [The supplied sample view’s model API differs from the app] → Recreate only its presentation and interactions on top of current domain/session types instead of importing the sample unchanged.
- [A portfolio can refresh while selection changes elsewhere] → Key row state by stable wallet ID and reconcile it whenever the session snapshot changes.
- [Partial portfolio failures can create mixed fresh/stale rows] → Preserve usable data, mark failed rows, and provide one retry action without hiding successful rows.

## Migration Plan

Add the route, dependency plumbing, view model, view, selector callback, and tests as an additive release. No data migration is required. Rollback consists of removing the destination and restoring the prior selector action; saved wallet and portfolio data remain compatible.

## Open Questions

None. The supplied screenshot and existing Add Wallet header establish the visual target, and existing repositories/session APIs cover the required behavior.
