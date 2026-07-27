# wallet-list-selection Specification

## Purpose
Define how users access, view, and select wallets from the full wallet list while preserving portfolio-loading and persistence behavior.

## Requirements

### Requirement: Selector links to the full wallet list
The wallet selector SHALL replace the nonfunctional “Wallet details” entry with a “Wallet list” navigation action that includes a trailing right chevron.

#### Scenario: Open wallet list from selector
- **WHEN** the user activates “Wallet list” in the wallet selector
- **THEN** the selector is dismissed and the full wallet list page is opened

#### Scenario: Compact selection remains available
- **WHEN** the wallet selector contains saved wallets
- **THEN** the user can still select a wallet directly from the compact selector without opening the full wallet list

### Requirement: Wallet list uses the requested page header
The wallet list page SHALL use the app theme and the same back-button and title treatment as the Add Wallet page, with the title “Wallets” and a trailing add button.

#### Scenario: Return from wallet list
- **WHEN** the user activates the wallet list back button
- **THEN** the app returns to the wallet home page without changing the active wallet

#### Scenario: Add from wallet list
- **WHEN** the user activates the wallet list add button
- **THEN** the existing Add Wallet flow is opened

### Requirement: Wallet list presents every saved wallet
The wallet list page SHALL present saved wallets in snapshot order as scrollable cards showing the wallet color, name, shortened address, “Ethereum” network, formatted USD portfolio total, and asset count.

#### Scenario: Present populated list
- **WHEN** the saved-wallet snapshot contains one or more wallets and portfolio data is available
- **THEN** one card per wallet is shown with its identity and portfolio summary

#### Scenario: Present active wallet
- **WHEN** a wallet ID matches the snapshot’s selected wallet ID
- **THEN** that wallet card shows an “Active” badge, selected accessibility state, and accent outline

#### Scenario: Present empty list
- **WHEN** the saved-wallet snapshot is empty
- **THEN** the page explains that there are no wallets and directs the user to the add button

### Requirement: Portfolio summaries load without blocking wallet identity
The wallet list SHALL load each wallet portfolio with the existing cache-first repository policy while keeping saved-wallet identity content visible.

#### Scenario: Portfolio is loading without cached data
- **WHEN** a wallet has not yet emitted cached or fresh portfolio data
- **THEN** its card remains visible and shows a loading placeholder for portfolio summary fields

#### Scenario: Cached data precedes fresh data
- **WHEN** the repository emits a cached portfolio followed by a fresh portfolio
- **THEN** the card first shows the cached summary and then replaces it with the fresh summary

#### Scenario: One portfolio load fails
- **WHEN** one wallet portfolio fails and other wallet portfolios succeed
- **THEN** successful cards retain their summaries, the failed card shows unavailable summary fields, and the page offers a retry action

#### Scenario: Refresh fails after cached data
- **WHEN** a cached portfolio was shown and its subsequent refresh fails
- **THEN** the cached summary remains visible and the failed load remains retryable

### Requirement: Wallet selection is persisted before leaving the list
The wallet list SHALL request selection through `WalletSession` and SHALL return to wallet home only after selection succeeds.

#### Scenario: Select a different wallet
- **WHEN** the user activates a non-active wallet card and persistence succeeds
- **THEN** that wallet becomes the selected wallet and the app returns to wallet home

#### Scenario: Select the active wallet
- **WHEN** the user activates the already active wallet card
- **THEN** the selection remains unchanged and the app returns to wallet home

#### Scenario: Wallet selection fails
- **WHEN** the user activates a wallet card and persistence fails
- **THEN** the wallet list remains open, the previous active wallet remains selected, and a recoverable error is shown

#### Scenario: Return after a failed selection
- **WHEN** the user leaves the wallet list with the back button after a selection failure
- **THEN** the selection error is cleared and the wallet home page does not repeat it
