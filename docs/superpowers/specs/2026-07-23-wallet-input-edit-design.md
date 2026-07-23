# Wallet Input and Editing Design

## Goal

Add the first-wallet import flow to the existing empty wallet card, persist the wallet across launches, load the imported address's portfolio, and reuse the form to edit or delete that wallet.

This release exposes one import opportunity only. The persistence model must support multiple wallets later, but after the first wallet is added the empty-card entry point disappears and no other add-wallet control is shown.

## Starting Point

The current `origin/main` implementation already provides:

- An empty wallet card and populated wallet card on the home screen.
- SwiftData-backed native-token, portfolio, and transaction caches.
- A validated, lowercase-normalizing `EVMAddress` domain value.
- Cache-first token and address-portfolio repository operations.
- Home-screen loading, refresh, error, and retry behavior.

The supplied `AddWalletView.swift` is a layout reference rather than drop-in code because it depends on wallet types not present in this repository. The supplied `Wallet-selection.png` defines the visual direction for the form.

## Scope

This iteration includes:

- Navigation from the empty wallet card to an add-wallet form.
- Required wallet name and EVM address validation.
- Five predefined wallet-card colors with a live preview.
- Durable local wallet persistence using SwiftData.
- A persistence model that can hold multiple wallets and a persisted selected-wallet identity.
- Loading the selected address's portfolio after creation and on later launches.
- A populated wallet card using the saved name, address, and gradient.
- Edit navigation from the wallet-name/edit region.
- Editing the saved name and card color while keeping the address and Ethereum network immutable.
- Confirmed wallet deletion, including removal of the address's cached portfolio and transaction data.
- Unit, persistence, view-model, UI, and simulator verification.

This iteration excludes:

- Generating a private key or wallet address.
- Importing private keys or seed phrases.
- Adding a second wallet through the UI.
- A wallet-selection interface.
- Editing a saved wallet address or network.
- Supporting networks other than Ethereum.

## Architecture

### Saved wallet domain value

`SavedWallet` is the UI-independent wallet identity. It contains:

- A stable UUID used by persistence, selection, and edit routes.
- A trimmed display name.
- A normalized `EVMAddress`.
- A predefined `WalletCardColor` value.
- A creation date used for deterministic ordering.

`WalletCardColor` is a stable raw-value enum rather than a SwiftUI `Color`. It defines the five approved blue, purple, pink, teal, and amber gradients at the view boundary and can round-trip through persistence.

### Saved wallet persistence

`SavedWalletStore` is a focused SwiftData-backed store that remains separate from the API cache store. Its protocol provides operations to:

- Load all saved wallets in creation order.
- Load and update the persisted selected-wallet ID.
- Atomically add the first wallet and select it after verifying that persistent storage is empty.
- Update only a wallet's name and card color.
- Delete a wallet.

The schema can store multiple wallet records even though the current UI creates only the first one. The first-wallet operation checks persistent state and saves the wallet plus its selected-wallet reference in one SwiftData transaction. This prevents duplicate navigation, repeated submission, or a partial selection write from leaving an inaccessible wallet. A future multi-wallet flow can add a separate unrestricted insert operation without changing the schema.

The saved-wallet models join the existing SwiftData schema and model container. Production and test composition inject the saved-wallet store rather than letting views construct a `ModelContext`.

### Wallet session

`WalletSession` is the app-level observable owner of selected-wallet state. It:

- Loads persisted wallets and selection at startup.
- Exposes the selected wallet to the home screen.
- Coordinates add, update, and delete operations.
- Changes published state only after the corresponding persistence operation succeeds.
- Makes a newly added wallet the selected wallet.
- Resolves a missing or stale selected-wallet ID to the first wallet in creation order and persists that repair.

Views do not read SwiftData directly. `WalletHomeViewModel` observes or receives session changes and loads the selected address through the existing token repository.

### Navigation

The app uses one `NavigationStack` with typed routes:

- `.addWallet`
- `.editWallet(walletID)`

Both routes render the same wallet form with explicit add or edit configuration. The route carries only stable identity; edit mode resolves the latest wallet value from `WalletSession` so it does not edit a stale copied record.

## Form Design

The form follows the supplied reference and uses the app's existing theme values in light and dark mode. From top to bottom it contains:

1. A custom back control and mode-specific title.
2. A live wallet-card preview using the selected gradient.
3. Wallet name label and text field.
4. Address label and field or read-only value.
5. A locked Ethereum network row and supporting text.
6. Five predefined card-color controls.
7. A full-width primary action.
8. A destructive delete action in edit mode only.

The content scrolls when needed and remains usable with the keyboard and accessibility text sizes. Controls use stable accessibility labels and identifiers. The preview uses light foreground content over every gradient and shows the current name plus shortened address.

### Add mode

- Title: `Add wallet`.
- Name and address are editable.
- Primary action: `Add wallet`.
- The address placeholder requires an imported address and does not offer generation.
- A successful add persists and selects the wallet, dismisses the form, and starts portfolio loading on the home screen.

### Edit mode

- Title: `Edit wallet`.
- The form starts with the saved name, address, network, and color.
- Name and card color are editable.
- Address and Ethereum network are visible but read-only.
- Primary action: `Save changes`.
- Destructive action: `Delete wallet`.
- Saving updates the home card and returns home after persistence succeeds.

Deleting first presents a confirmation dialog that clearly names the destructive outcome. Cancel leaves the wallet unchanged. Confirm runs the deletion flow and returns to the empty home state only after the saved-wallet record is gone.

## Home-Screen Interactions

`EmptyWalletCardView` becomes a semantic button that navigates to `.addWallet`. Once any wallet is persisted, the empty card is replaced by the selected wallet card and no add-wallet entry point remains in this release.

The populated card uses the saved gradient rather than the existing glass fill. It retains the current minimum height and responsive layout.

The top identity row has two independent interaction regions:

- The wallet-name region includes an edit icon. The entire name/edit region navigates to `.editWallet(walletID)`.
- The address region keeps the existing copy behavior and confirmation state. It never triggers edit navigation.

The rest of the card is not required to navigate, preventing accidental edits when a user intends to inspect the balance.

## Validation

### Wallet name

- Leading and trailing whitespace is removed before validation and persistence.
- The trimmed value is required.
- The maximum is 20 Swift characters.
- Input beyond 20 characters is prevented.
- An inline message appears after the field has been interacted with or submission is attempted.

### Address

- Leading and trailing whitespace is removed before validation.
- Add mode requires `0x` followed by exactly 40 hexadecimal characters.
- The existing `EVMAddress` value performs final validation and normalizes the value to lowercase.
- Edit mode never accepts address input and preserves the stored normalized address.
- An inline invalid-address message appears after interaction or attempted submission.

The add action remains disabled until both fields are valid. The edit action requires a valid name. Rapid repeated action taps cannot create or save duplicate operations while a persistence request is in progress.

## Data Flow

### Application launch

1. App composition creates one SwiftData container containing cache and saved-wallet models.
2. `WalletSession` loads saved wallets and the selected-wallet ID.
3. With no saved wallet, home shows the empty wallet card.
4. With a selected wallet, home constructs its card from saved identity and requests `TokenRepository.portfolio(address:policy:)`.
5. Cached portfolio data renders immediately when present.
6. Missing or expired data triggers the existing network refresh policy.
7. Fresh portfolio data replaces the cached token rows and recalculates total value.

### Add

1. The form validates and normalizes name and address.
2. `WalletSession` asks `SavedWalletStore` to atomically persist and select the first wallet.
3. Only after that transaction succeeds does the session publish the selected wallet.
4. Navigation returns home.
5. Home begins cache-first portfolio loading for that address.

### Edit

1. The form validates the trimmed name.
2. `SavedWalletStore` updates only name and card color for the routed wallet ID.
3. On success, `WalletSession` publishes the updated wallet and navigation returns home.
4. Because the address is unchanged, existing portfolio data remains valid and no forced refresh is required.

### Delete

1. The user confirms deletion.
2. Address-linked portfolio and transaction caches are purged first.
3. If cache purging succeeds, the saved-wallet record and matching selected-wallet reference are deleted.
4. `WalletSession` publishes the next persisted wallet if one exists; in this release it publishes no selection and home shows the empty card.

Native-token metadata is not deleted because it is not address-linked. Cache-first repository state and any in-flight request for the deleted selection must not repopulate the visible home screen after the session changes.

## Error Handling

- A saved-wallet read failure presents a recoverable home-level error and Retry control rather than incorrectly presenting a valid empty-wallet state.
- Add or edit persistence failure leaves the form open, preserves user input, stops its progress state, and shows a concise inline error.
- Portfolio failure never deletes or hides the saved wallet. Cached balances remain when available, and the existing error and Retry presentation is reused.
- If address-linked cache purging fails, deletion stops and the wallet remains persisted and visible.
- If saved-wallet deletion fails after caches were purged, the wallet remains visible; its portfolio can be fetched again. This order prioritizes not leaving address-linked cache behind for a wallet that appears deleted.
- Successful deletion clears obsolete portfolio errors and prevents late asynchronous results for the deleted address from updating the home screen.

## Verification

### Domain and validation tests

- Empty and whitespace-only names fail.
- Leading and trailing name whitespace is removed.
- Names of exactly 20 characters pass and longer input is capped.
- Valid EVM addresses pass and normalize to lowercase.
- Missing prefix, incorrect length, and non-hexadecimal bodies fail.
- Every card-color raw value round-trips and maps to its intended gradient.

### Persistence and session tests

- A wallet add round-trips name, address, card color, ID, and creation date.
- A fresh container using the same persistent store reloads the wallet and selection.
- The schema stores multiple wallets in deterministic creation order.
- The atomic first-wallet operation rejects creating a second wallet while one exists.
- Editing changes only name and card color.
- Stale selection resolves to the first persisted wallet.
- Confirmed deletion removes the wallet, its selection, its portfolio cache, and all transaction pages for that address.
- Deletion preserves native metadata and cache records for other addresses.
- Cache-purge failure leaves the wallet intact.
- Saved-wallet deletion failure after purge leaves the wallet intact and reloadable.

### View-model and repository tests

- Launch with a selected wallet requests its normalized address portfolio.
- Cached and fresh portfolio events update rows and total value.
- A selected-wallet change invalidates earlier in-flight results.
- Portfolio errors retain the wallet identity and cached rows and expose Retry.
- Updating only name or color does not force a portfolio request.
- Deleting the selected wallet returns home to the empty state.

### UI tests

- The empty card opens add mode.
- Invalid fields show messages and keep Add disabled.
- Valid submission returns to a populated home card using the chosen gradient.
- A persisted fixture starts in the populated state after relaunch.
- The name/edit region opens edit mode.
- The address control copies without navigating.
- Edit mode shows the correct title, read-only address, locked network, save action, and delete action.
- Saving changes updates the home name and gradient.
- Canceling delete confirmation preserves the wallet.
- Confirming deletion returns to the empty card.
- Existing theme, token loading, retry, pull-to-refresh, pinned-header, and copy behavior remain functional.

Finally, all unit and UI tests pass on an iOS simulator, and the application builds for an iOS simulator with code signing disabled.

## Completion Criteria

The work is complete when the first wallet can be added from the empty card, persists across relaunches, loads its cached/fresh address portfolio, displays its saved gradient, can be renamed or recolored through the card's edit region, can be deleted only after confirmation with all address-linked cache removed, exposes no second-wallet import UI, preserves independent address-copy behavior, and passes the full verification suite.
