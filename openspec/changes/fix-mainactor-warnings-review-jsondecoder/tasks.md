## 1. Correct Actor Isolation

- [x] 1.1 Mark the immutable cache payload/metadata declarations and cache version in `WalletStore.swift` as nonisolated without changing their stored properties, Codable conformances, or payload version.
- [x] 1.2 Mark `RefreshPolicy` as a nonisolated value type so its `Equatable` conformance is available to Swift Testing's nonisolated comparison code.
- [x] 1.3 Review every isolation edit to confirm that no actor-owning service, UI type, build setting, warning suppression, or unsafe isolation escape was changed.

## 2. Bound JSON Decoder Ownership

- [x] 2.1 Keep independent one-shot decode call sites operation-local and confirm that no codebase-wide shared decoder or decoder-provider abstraction is introduced.
- [x] 2.2 Reuse one function-local `JSONDecoder` within the `WalletStore` metadata record loop so repeated records do not repeatedly initialize a decoder during the same serialized operation.

## 3. Verify Diagnostics and Behavior

- [x] 3.1 Run the existing unit tests covering wallet cache serialization, API/repository decoding, and pull-refresh policy behavior; fix only regressions caused by this change.
- [x] 3.2 Build the full `sevenwallet` scheme for testing from a fresh derived-data location and verify that project Swift sources emit no MainActor or actor-isolation warnings.
- [x] 3.3 Confirm the final diff contains no cache schema/version, serialized-property, public API, dependency, or target build-setting changes.
