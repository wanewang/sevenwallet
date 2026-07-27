## Why

The project builds successfully, but Xcode reports MainActor-isolation warnings in persistence value types and `RefreshPolicy` test comparisons; several are explicitly described as Swift 6 errors. The codebase also creates default `JSONDecoder` instances at each decode site, so this change should resolve the concurrency issues while making an intentional, concurrency-safe decoder lifecycle decision.

## What Changes

- Remove all MainActor-related compiler warnings emitted by the `sevenwallet` scheme's build-for-testing without weakening the target's default MainActor isolation.
- Make pure data-transfer, cache-payload, and policy value types explicitly usable outside the MainActor where their semantics do not require UI isolation.
- Preserve MainActor isolation for UI state and other genuinely main-thread-bound behavior.
- Keep default-configured `JSONDecoder` instances local to decode operations; do not introduce a shared mutable decoder singleton when the current call sites have no shared configuration or measured allocation bottleneck.
- Add verification that production and test targets continue to compile and their relevant behavior remains covered.

## Capabilities

### New Capabilities

- `swift-concurrency-hygiene`: Defines actor-isolation boundaries and warning-free build expectations for pure value types, serialization, and test comparisons.

### Modified Capabilities

None.

## Impact

- Affected production areas: persistence cache payloads and metadata in `WalletStore.swift`, shared repository policy types, and any additional source identified by the verification build.
- Affected tests: `PullRefreshCoordinatorTests` and existing persistence/repository test coverage used to guard behavior.
- Serialization behavior and stored payload formats remain unchanged.
- No public API, dependency, build-setting, or data-migration changes are expected.
