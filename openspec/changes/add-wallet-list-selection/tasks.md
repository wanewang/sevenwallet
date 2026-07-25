## 1. Navigation and Dependency Plumbing

- [x] 1.1 Add a wallet-list route and carry the shared `TokenRepositoryProtocol` on `WalletAppState`, populating the new field at all three `AppDependencies.makeAppState` construction sites (live, `fixtureState`, `unavailableState`).
- [x] 1.2 Add the `onShowWalletList` callback through `WalletHomeView` and `WalletSelectorView`, then replace “Wallet details” with a functional “Wallet list” row and trailing `chevron.right` while preserving compact selection and add-wallet actions.
- [x] 1.3 Register the wallet-list destination in `WalletRootView` and wire its back, add, successful selection, and failed selection behavior to the existing path and `WalletSession`.
- [x] 1.4 Add `WalletSession.clearSelectionError()` and call it when the wallet-list destination is popped so `WalletHomeView` does not repeat a selection error already shown on the list.

## 2. Wallet List Presentation Model

- [x] 2.1 Add focused `WalletListViewModel` tests for saved-wallet ordering, total and asset-count calculation, cached-to-fresh updates, independent row failures, retry behavior, stale-data preservation, wallet-set reconciliation/cancellation, and an empty snapshot producing no rows and starting no portfolio loads.
- [x] 2.2 Implement `WalletListViewModel` and row state keyed by wallet ID, loading each portfolio independently with `.ifExpired` and exposing loading, formatted summary, unavailable, and retry states required by the tests.

## 3. Wallet List Interface

- [x] 3.1 Build `WalletListView` with the themed Add Wallet-style 44-point back/title header, “Wallets” title, trailing accent add button, hidden system navigation bar, and scrollable/empty layouts.
- [x] 3.2 Build wallet cards matching the supplied reference: color gradient, name, shortened monospaced address, Ethereum label, formatted total, asset count, loading/unavailable placeholders, Active capsule, and accent outline.
- [x] 3.3 Add the inline portfolio retry and wallet-selection error presentations, plus stable accessibility identifiers, labels, and selected traits for controls and rows.

## 4. End-to-End Verification

- [x] 4.1 Extend UI tests to open “Wallet list” from the selector, verify selector dismissal and list content/active state, switch wallets, return with back, and open Add Wallet from the plus button.
- [x] 4.2 Add a UI test that opens the wallet list with the no-saved-wallets fixture and verifies the empty-state copy pointing at the add button.
- [x] 4.3 Run unit and UI test targets, build the app, and compare the wallet list in dark and light themes against the supplied layout and `WalletFormView` header styling.
