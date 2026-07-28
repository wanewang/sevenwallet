# Follow-ups

Deferred work that is understood but deliberately out of scope for the change
that surfaced it. Each entry states the problem, why it was deferred, and what a
fix would involve.

## Tie the token Retry action to the view's lifetime

**Source:** review of `feat/token-market-enrichment` (PR #11)
**Area:** `sevenwallet/View/Wallet/WalletHomePage.swift`
**Status:** open

### Problem

The compact token error's Retry button starts unstructured work:

```swift
Button("Retry") {
    Task { await viewModel.retryTokens() }
}
```

`Task { }` here has no relationship to the view that created it. It is not the
`.task(id: walletLoadKey)` modifier's child, so SwiftUI does not cancel it when
the view disappears or when `walletLoadKey` changes. The same applies to the
`.refreshable` closure.

Consequence: tapping Retry and immediately switching wallets leaves the retry
running against the previous wallet. `WalletHomeViewModel.consume` bumps
`requestGeneration`, so the stale result is correctly discarded and no wrong
state is ever published — this is wasted work, not a correctness bug — but the
work itself continues to completion.

### Why it was deferred

Repository-level coalescing and suspension handling (`TokenRepository`
`marketTasks`, added in the same review pass) bound the damage considerably: a
duplicate retry now joins the in-flight attempt chain instead of starting a
second one, and deleting a wallet cancels that chain outright. What remains is a
single redundant chain in a narrow interleaving.

Fixing it properly means changing where task ownership lives — moving the retry
task onto the view model so it can be cancelled from `updateWallets` and
`updateLoadingEligibility` — which is a structural change to a view model whose
staleness strategy is currently generation counters, not cancellation. That did
not belong in a review-fix pass.

### Sketch of a fix

Hold the retry task on the view model and cancel it wherever the generation is
already bumped:

```swift
private var retryTask: Task<Void, Never>?

func retryTokens() {
    retryTask?.cancel()
    retryTask = Task { [weak self] in await self?.consume(policy: .ifExpired) }
}
```

with `retryTask?.cancel()` added to `updateWallets(_:)` and
`updateLoadingEligibility(_:)`. Note this makes `retryTokens` synchronous, which
changes its call sites and its tests — several existing tests `await
home.retryTokens()` and rely on it completing before they assert.

Decide at that point whether `refreshTokens` should get the same treatment.
Pull-to-refresh is already tied to the `.refreshable` scope, so it may not need
it.

### Verification

A test that starts a retry, switches wallets mid-flight, and asserts the
repository observes no further attempts for the original address — the existing
`obsoleteMarketResultCannotOverwriteReplacementWallet` is the closest shape to
build on.

---

## Distinguish a total enrichment join miss from a successful no-op

**Source:** review of `feat/token-market-enrichment` (PR #11)
**Area:** `WalletHomeViewModel.enrich(_:with:)`, `TokenIdentifiable.key`
**Status:** open

`TokenIdentifiable.key` is `"\(symbol):\(tokenAddress?.lowercased() ?? "native")"`.
It lowercases the address but not the symbol. Before market enrichment, both
sides of every comparison came from `/v1/wallet/{address}`, so casing agreed for
free. Enrichment now joins that response against `/v1/tokens/{address}`.

If the two endpoints ever disagree on symbol casing, or on how the native token
is represented, `marketsByID[token.id]` misses for *every* token. The result is
HTTP 200, `resourceState = .loaded`, no error message, spinner off, prices
unchanged — a completely dead feature reported as total success.

A non-empty market response that matches zero holdings is not a legitimate
outcome. Treating it as a failure (or at minimum logging it via `AppLog.market`,
which now exists) would make the breakage visible. Needs no spec change.

Related and lower priority: `Dictionary(_:uniquingKeysWith:)` silently drops
duplicate market entries for a key, and `tokenAddress` is a raw `String?` on both
types while a normalizing `EVMAddress` exists in the same module.

---

## Make market script exhaustion loud in the test double

**Source:** review of `feat/token-market-enrichment` (PR #11)
**Area:** `sevenwalletTests/Support/RepositoryTestDoubles.swift`
**Status:** open

`PortfolioTokenRepositorySpy.tokenMarkets` returns a successful empty portfolio
when `marketScripts` is exhausted, while the `portfolio` method directly above it
traps via `removeFirst()`. A test that provokes more market requests than it
scripted passes quietly. Because an empty market list is *also* the correct
result for a token with no market data, an under-scripted test and a genuinely
empty response are indistinguishable.

Dropping the `guard !marketScripts.isEmpty` fallback in favour of
`marketScripts.removeFirst()` would match the sibling method. Tests that want the
empty-response behaviour should script it explicitly.
