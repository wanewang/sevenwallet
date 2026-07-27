## Context

The app target enables approachable concurrency with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. A baseline Xcode 26.2 build-for-testing succeeds but emits warnings that will become errors in Swift 6 mode:

- `WalletStore`, a SwiftData `@ModelActor`, uses cache payload and metadata value types whose declarations, Codable conformances, members, and version constant inherit MainActor isolation from the target default.
- Swift Testing expands `RefreshPolicy` equality checks in a nonisolated context, but the enum's `Equatable` conformance currently inherits MainActor isolation.

There are ten direct `JSONDecoder()` constructions: nine in production and one in tests. Every instance uses the default configuration. Most call sites decode once; the metadata-loading loop is the only site that constructs a decoder repeatedly within one operation.

## Goals / Non-Goals

**Goals:**

- Eliminate all MainActor-related Swift warnings from the app, unit-test, and UI-test build-for-testing targets.
- Express the intended isolation of immutable serialization and policy values without changing behavior.
- Preserve SwiftData model-actor ownership and UI MainActor ownership.
- Establish a safe, simple decoder lifecycle rule for the current default-configured call sites.

**Non-Goals:**

- Changing the target-wide default actor isolation or completing a full Swift 6 language-mode migration.
- Suppressing diagnostics with unsafe isolation escapes or warning flags.
- Refactoring unrelated repository, networking, persistence, or UI code.
- Changing Codable keys, payload formats, cache versions, or invalid-data behavior.
- Introducing codec dependency injection, a global codec abstraction, or performance optimization without measurements.

## Decisions

### Mark only pure cross-actor values as nonisolated

Declare the immutable cache payload/metadata types, their file-scoped cache version, and `RefreshPolicy` as `nonisolated` where needed. This makes their synthesized conformances and value-only members available to `WalletStore`'s model actor and Swift Testing's nonisolated macro expansion. Keep `WalletStore` on its generated model actor and leave UI/view-model types on the MainActor.

Alternatives considered:

- Moving `WalletStore` work to the MainActor would undermine SwiftData's generated actor boundary and serialize persistence work on the UI executor.
- Disabling default MainActor isolation would be a broad project policy change with unrelated effects.
- Adding `@MainActor` to tests would not correctly model a pure policy value and may not resolve nonisolated macro-generated comparisons.
- Unsafe isolation annotations or warning suppression would defer errors instead of establishing correct ownership.

### Keep JSON decoders operation-local

Do not introduce a codebase-wide shared `JSONDecoder`. The current call sites have no shared configuration, and a global mutable formatter would create hidden coupling and require the codebase to reason about concurrent access across networking, model-actor persistence, and tests. Continue creating one decoder for each independent decode operation. Where one synchronous operation decodes multiple records, create one local decoder before the loop and reuse it only for that operation.

If a shared decoding policy is needed later, prefer a factory that returns a newly configured decoder. If profiling later justifies instance reuse, contain that instance within a single actor or service rather than making it process-global.

Alternatives considered:

- A static shared decoder reduces visible initializers but introduces shared mutable state without a current configuration or measured performance benefit.
- A new decoder-provider abstraction would add indirection for ten default-configured call sites and is not justified by current behavior.

### Verify diagnostics and behavior separately

Use the `sevenwallet` scheme's build-for-testing as the diagnostic acceptance check, inspecting compiler output for MainActor/actor-isolation warnings. Run the existing unit tests covering cache serialization, repositories, API decoding, and pull-refresh policy behavior to confirm the isolation annotations do not change runtime results.

## Risks / Trade-offs

- [A type is marked nonisolated even though it owns UI or mutable state] → Limit changes to immutable value types and constants implicated by diagnostics; do not alter actor-owning services or view models.
- [Synthesized Codable or Equatable behavior changes unexpectedly] → Preserve declarations, properties, conformance lists, cache version, and test the existing serialization/equality behavior.
- [Operation-local decoders retain small allocation costs] → Accept the simpler ownership model until profiling identifies decoding setup as material; reuse only within an already serialized local operation.
- [Incremental compilation hides a warning] → Verify with a fresh derived-data location or a build that recompiles the affected targets and inspect the complete diagnostic output.

## Migration Plan

1. Add the minimal isolation declarations to the warning-producing pure values and constant.
2. Hoist decoder construction out of any same-operation decode loop without creating shared state.
3. Run targeted unit tests, then build all scheme targets for testing and confirm no MainActor-related warnings remain.
4. No data migration or staged rollout is required. Rollback consists of reverting the source annotations/local decoder change; persisted payloads remain compatible.

## Open Questions

None. A shared decoder should only be reconsidered if future configuration requirements or profiling data provide a concrete reason.
