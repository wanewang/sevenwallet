## ADDED Requirements

### Requirement: MainActor-clean build
The project SHALL compile every target included by the `sevenwallet` scheme's build-for-testing action without MainActor or actor-isolation warnings from project Swift sources.

#### Scenario: Build all targets for testing
- **WHEN** the `sevenwallet` scheme is built for testing with the project's configured default MainActor isolation
- **THEN** compiler output contains no MainActor or actor-isolation warning attributed to app, unit-test, or UI-test Swift source

### Requirement: Correct isolation for pure values
Immutable policy and serialization values that do not own UI state SHALL be usable from their owning service actor and from nonisolated conformance consumers without an implicit MainActor hop.

#### Scenario: Model actor serializes cache values
- **WHEN** `WalletStore` encodes, decodes, compares, or maps its immutable cache payload and metadata values on the SwiftData model actor
- **THEN** those operations complete without crossing to the MainActor

#### Scenario: Test compares a policy value
- **WHEN** Swift Testing evaluates equality for `RefreshPolicy` in macro-generated nonisolated code
- **THEN** the conformance is available without a MainActor hop

### Requirement: Existing serialization behavior is preserved
Isolation corrections SHALL NOT change encoded cache formats, cache versioning, decoded domain values, or invalid-payload handling.

#### Scenario: Read existing cache payloads
- **WHEN** the persistence layer reads a cache payload produced before this change
- **THEN** it produces the same domain value or the same invalid-cache outcome as before the change

### Requirement: Decoder instances have bounded ownership
Default-configured JSON decoder instances SHALL be local to one decode operation or one already-serialized operation scope and SHALL NOT be stored as shared mutable process-wide state.

#### Scenario: Independent components decode concurrently
- **WHEN** networking, persistence, or test code performs independent default-configured JSON decoding
- **THEN** the components do not concurrently access a codebase-wide shared decoder instance

#### Scenario: One operation decodes multiple records
- **WHEN** one synchronous actor-isolated operation decodes multiple records in a loop
- **THEN** it may reuse one decoder whose lifetime and access remain local to that operation
