# WalletHomeView Design

## Goal

Build `WalletHomeView` as the app's first wallet dashboard. The screen presents a selected wallet, its calculated USD value, and a scrollable list of assets while preserving a fixed top bar. This iteration uses static data behind view models so a later API-backed source can replace the data construction without changing the view hierarchy.

## Scope

This iteration includes:

- A fixed 64-point top bar.
- A wallet summary card that scrolls with the page.
- An Assets header and a four-row asset list.
- Light/dark theme switching.
- Copying the wallet's full address.
- Static ETH, BTC, SOL, and USDC data.
- Separate home, wallet-card, and asset-row view models.

Wallet selection and asset management are styled as buttons but intentionally perform no action. There is no API integration, navigation, loading state, or network-error state in this iteration.

## Architecture

Use three Observation-based reference types:

### `WalletHomeViewModel`

- Owns `isThemeLight`, initially `false` to preserve the current dark-theme default.
- Owns the shared `[AssetViewModel]` collection.
- Owns `WalletCardViewModel`.
- Provides a static sample-data factory for this iteration.
- Toggles `isThemeLight` for the top-right theme button.

### `WalletCardViewModel`

- Owns the wallet name and full address.
- Receives the same `AssetViewModel` instances held by `WalletHomeViewModel`.
- Exposes a shortened address containing the first six characters, an ellipsis, and the last six characters. Addresses of 12 characters or fewer remain unchanged.
- Calculates total wallet value by summing every asset's calculated USD value.
- Exposes formatted total-value text.

### `AssetViewModel`

- Owns symbol, balance, current USD unit price, daily percentage change, icon text, and icon color.
- Calculates its USD value as `balance * currentPrice`.
- Exposes formatted USD value, token balance, and percentage-change text.
- Exposes whether the daily change is nonnegative so the view can choose `Theme.pos` or `Theme.neg`.

The shared asset instances are the single source of truth. Both the wallet summary and the asset rows read from them, so later balance or price changes update both parts of the screen without synchronizing duplicate values.

No separate domain-model or service layer is needed for static data. The sample-data factory is the replacement boundary for a future API-backed implementation.

## View Hierarchy

`WalletHomeView` remains the app entry view and uses this structure:

1. A root themed background that extends behind system areas.
2. A vertical layout that otherwise respects the safe area.
3. `WalletTopBar`, fixed above the scrolling content.
4. One vertical `ScrollView` containing:
   - `WalletCardView`
   - Assets section header
   - A soft-glass asset-list card containing `AssetRowView` rows

The wallet card and Assets section scroll away together. Only the top bar remains fixed.

## Top Bar

- Exact height: 64 points.
- Horizontal page padding: 16 points.
- Both buttons: 48 by 48 points.
- Left wallet-selection button: `rectangle.grid.1x2` followed by `chevron.down`; no wallet name is shown. The button has no action in this iteration.
- Right theme button: `sun.max` when `isThemeLight` is true and `moon` when false. Tapping it toggles the theme immediately.
- Both controls have accessibility labels and stable identifiers for UI verification.

## Wallet Card

- Uses `theme.glass` as its fill and a one-point `theme.edge` border.
- Uses a rounded rectangle and 16-point internal spacing.
- Top row: wallet name aligned left; shortened address and copy icon aligned right.
- The copy icon writes the full, unshortened address to the system pasteboard. It does not show a confirmation banner or change state in this iteration.
- Below the identity row: uppercase `TOTAL VALUE` secondary label followed by a prominent formatted USD value.
- The card's total is always derived from the shared assets and is never stored separately.

## Assets Section

- Header: `Assets` aligned left.
- Right control: `slider.horizontal.3` and `Manage` inside a bordered rounded rectangle. It has no action in this iteration.
- The list uses a `LazyVStack` inside the page's existing `ScrollView`; it does not create a second scrolling region.
- The list container uses `theme.glass`, a one-point `theme.edge` border, and the same corner treatment as the wallet card.
- Adjacent rows are separated by `theme.divider` hairlines.

Each asset row contains:

- Left: a colored circular icon containing a local initial or simple symbol, with no asset-catalog or remote image dependency.
- Middle: symbol on top and formatted daily percentage change below.
- Right: calculated USD value on top and token balance with symbol below, both right-aligned.
- Positive and zero daily change use `Theme.pos`; negative change uses `Theme.neg`.

## Static Sample Data

The sample factory creates four assets with representative nonzero values:

| Asset | Balance | USD unit price | Daily change | Icon text |
| --- | ---: | ---: | ---: | --- |
| ETH | 4.25 | 2,936.52 | +2.48% | `Ξ` |
| BTC | 0.0934 | 104,022.48 | +1.12% | `₿` |
| SOL | 18.42 | 142.54 | +4.06% | `S` |
| USDC | 1,500 | 1.00 | -0.03% | `$` |

At these values, the asset totals round to $12,480.21, $9,715.70, $2,625.59, and $1,500.00. The wallet total rounds to $26,321.50.

The sample wallet name is `Main Wallet`. Its address must be longer than 12 characters so the six-plus-six shortening behavior is visible.

## Formatting and Theme

- Reuse the existing `Theme` palette and `Fmt` number helpers.
- Adjust address shortening from the current six-plus-four result to the required six-plus-six result.
- USD values always show two fractional digits.
- Token balances use the existing amount formatting and include their symbol in the row's secondary text.
- Percentage changes show an explicit plus sign only for positive values and two fractional digits for all values.
- The screen applies the matching SwiftUI color scheme when the theme changes.

## Edge Cases

- No assets: wallet total is `$0.00`, and the list container contains no rows.
- Address length of 12 characters or fewer: display the full address without an ellipsis.
- Zero daily change: display `0.00%` using the nonnegative color.
- Clipboard assignment uses the platform pasteboard and has no recoverable failure path in this local-only iteration.

## Verification

Unit tests cover:

- Asset USD value equals balance multiplied by unit price.
- Wallet total equals the sum of all shared asset values.
- Changing a shared asset updates the derived asset and wallet totals.
- Address shortening returns first six plus ellipsis plus last six.
- Short addresses remain unchanged.
- Positive, negative, and zero percentage formatting.

A focused UI test launches the app and verifies:

- Both top-bar buttons exist.
- The wallet name and total-value label exist.
- ETH, BTC, SOL, and USDC rows exist.
- The Manage control exists.

Finally, build the application for an iOS simulator with code signing disabled. Completion requires unit tests and the build to pass.
