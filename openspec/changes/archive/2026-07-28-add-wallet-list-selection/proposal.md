## Why

The wallet selector exposes a “Wallet details” action that does not lead anywhere, so users have no full-page place to review and switch between all saved wallets. A dedicated wallet list will make wallet management discoverable while matching the supplied product design and the app’s existing add-wallet flow.

## What Changes

- Replace the selector’s “Wallet details” action with a “Wallet list” action that includes a trailing right chevron and opens a dedicated page.
- Add a wallet list page styled like the supplied reference, with the same back-button and title treatment used by the Add Wallet page.
- Show each saved wallet’s color, name, shortened address, Ethereum network, portfolio total, asset count, and active state.
- Allow users to select a wallet from the list, persist the selection, and return to the wallet home page after a successful switch.
- Provide a header add button that opens the existing Add Wallet flow, plus clear empty, loading, and recoverable error states.
- Add automated coverage for selector navigation, list presentation, wallet switching, and add-wallet navigation.

## Capabilities

### New Capabilities

- `wallet-list-selection`: Full-page presentation of saved wallets and navigation for switching wallets or adding another wallet.

### Modified Capabilities

None.

## Impact

- Wallet navigation and destinations in `Screen` and `WalletRootView`, plus the shared token repository carried on `WalletAppState`.
- Wallet selector action layout and callbacks in `WalletSelectorView` and `WalletHomeView`.
- New SwiftUI wallet list view and presentation model using the existing `WalletSession`, wallet snapshot, theme, formatting, and token portfolio repository behavior.
- Wallet UI and presentation-model tests; no external API or persistence schema changes are expected.
