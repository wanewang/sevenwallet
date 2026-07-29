## MODIFIED Requirements

### Requirement: Wallet list uses the requested page header
The wallet list page SHALL use the app theme and the same back-button and title treatment as the Add Wallet page, with both pages rendering back navigation through the shared `WalletBackButton`, header actions styled through `WalletActionButtonStyle`, the title “Wallets”, and a trailing add button that opens the expanded import-method form.

#### Scenario: Present shared header actions
- **WHEN** Add Wallet or Wallet List presents its header
- **THEN** its back button uses the Wallet List's 44-point neutral rounded-rectangle treatment, while the Wallet List add button retains its accent treatment through the shared action-button style

#### Scenario: Return from wallet list
- **WHEN** the user activates the wallet list back button
- **THEN** the app returns to the wallet home page without changing the active wallet

#### Scenario: Add from wallet list
- **WHEN** the user activates the wallet list add button
- **THEN** Add Wallet opens with Watch address, Recovery phrase, and Private key methods

### Requirement: Wallet list presents every saved wallet
The wallet list page SHALL present saved wallets in snapshot order as scrollable cards showing the wallet color, name, shortened address, ownership status, “Ethereum” network, formatted USD portfolio total, and asset count.

#### Scenario: Present populated list
- **WHEN** the saved-wallet snapshot contains one or more wallets and portfolio data is available
- **THEN** one card per wallet is shown with its identity, Watch only or Imported ownership status, and portfolio summary

#### Scenario: Present active wallet
- **WHEN** a wallet ID matches the snapshot’s selected wallet ID
- **THEN** that wallet card shows an “Active” badge, selected accessibility state, and accent outline

#### Scenario: Present empty list
- **WHEN** the saved-wallet snapshot is empty
- **THEN** the page explains that there are no wallets and directs the user to the add button
