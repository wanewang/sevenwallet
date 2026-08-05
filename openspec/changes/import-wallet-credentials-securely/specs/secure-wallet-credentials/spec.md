## ADDED Requirements

### Requirement: Recovery phrases are strictly validated and normalized
The system SHALL accept only valid English BIP-39 recovery phrases containing exactly 12 or 24 words, SHALL treat an empty additional BIP-39 passphrase as fixed behavior, and SHALL convert accepted phrases to their entropy bytes before protected storage.

#### Scenario: Valid 12-word phrase
- **WHEN** a user enters a valid English 12-word BIP-39 phrase with mixed whitespace or letter case
- **THEN** the system normalizes the input, validates its checksum, and prepares 128-bit entropy without persisting the phrase text

#### Scenario: Valid 24-word phrase
- **WHEN** a user enters a valid English 24-word BIP-39 phrase
- **THEN** the system validates its checksum and prepares 256-bit entropy

#### Scenario: Unsupported or invalid phrase
- **WHEN** a phrase has an unsupported word count, unknown English word, invalid checksum, or requires a non-empty additional passphrase
- **THEN** the system rejects it without deriving, authenticating, or writing credential data

### Requirement: Ethereum private keys are strictly validated
The system SHALL accept a private key only when trimming surrounding whitespace and an optional `0x` prefix produces exactly 64 hexadecimal characters representing a valid 32-byte secp256k1 private scalar.

#### Scenario: Valid prefixed private key
- **WHEN** a user enters a valid 32-byte Ethereum private key with an uppercase `0x`-compatible hexadecimal representation and surrounding whitespace
- **THEN** the system prepares the same 32 key bytes for protected storage

#### Scenario: Invalid private key
- **WHEN** input has the wrong length, non-hexadecimal content, a zero scalar, or a scalar outside the secp256k1 range
- **THEN** the system rejects it without authenticating or writing credential data

#### Scenario: Input that only resembles hexadecimal
- **WHEN** input is 64 bytes long but contains sign prefixes such as `+` or `-`, or characters outside the ASCII range
- **THEN** the system rejects it rather than decoding it to unrelated key bytes or failing to parse it

### Requirement: Imported credentials derive a deterministic Ethereum address
The system SHALL derive recovery-phrase imports at `m/44'/60'/0'/0/0` and SHALL derive private-key imports directly, using Ethereum secp256k1 and Keccak address rules.

#### Scenario: Derive from recovery phrase
- **WHEN** a valid recovery phrase is prepared
- **THEN** the resulting normalized address matches the first Ethereum account at `m/44'/60'/0'/0/0`

#### Scenario: Derive from private key
- **WHEN** a valid private key is prepared
- **THEN** the resulting normalized address matches the Ethereum address for that exact key

### Requirement: Credential bytes use authenticated device-only storage
The system MUST store mnemonic entropy and private-key bytes only in a non-synchronizing Keychain item accessible only while a passcode-protected device is unlocked and protected by device-owner authentication.

#### Scenario: Store on a protected device
- **WHEN** device-owner authentication is available, the user accepts the import warning, and authentication succeeds
- **THEN** the system stores a versioned credential payload under an opaque reference with device-only user-presence access control

#### Scenario: Device protection is unavailable
- **WHEN** no device passcode or supported device-owner authentication is available
- **THEN** the system blocks credential-backed import and does not fall back to weaker Keychain, SwiftData, file, preferences, or cloud storage

#### Scenario: Import authentication is cancelled or fails
- **WHEN** device-owner authentication is cancelled or fails before credential storage
- **THEN** neither credential bytes nor credential-backed public metadata remain committed

#### Scenario: Credential is read later
- **WHEN** any future operation requests stored credential bytes
- **THEN** the Keychain requires Face ID, Touch ID, or device-passcode authentication for that read

### Requirement: Public persistence never contains secret material
The system MUST persist only public wallet metadata and an opaque credential reference in SwiftData, and MUST NOT place phrases, private keys, mnemonic entropy, derived private keys, or credential payloads in logs, analytics, errors, accessibility values, state restoration, fixtures representing real users, or crash messages.

#### Scenario: Credential-backed wallet is persisted
- **WHEN** a credential import succeeds
- **THEN** inspection of the SwiftData wallet record exposes the public address and opaque reference but no credential bytes or source kind

#### Scenario: An operation fails
- **WHEN** validation, authentication, Keychain, or SwiftData reports an error
- **THEN** user-visible and diagnostic error text contains no submitted secret or derived private data, and names the failed operation rather than reporting every Keychain failure as a storage failure

#### Scenario: Release builds are assembled
- **WHEN** the app is compiled for release
- **THEN** test fixtures that hold credential payloads in plaintext memory are excluded from the binary and cannot be selected by a launch argument

### Requirement: Cross-store imports do not orphan credentials
The system SHALL coordinate public wallet persistence and protected credential storage so a crash or failure converges to either a referenced credential-backed wallet or a watch-only wallet without an unreferenced Keychain secret.

#### Scenario: New credential import succeeds
- **WHEN** public metadata and protected storage both succeed
- **THEN** the new wallet is selected and published as credential-backed only after both writes complete

#### Scenario: Protected storage fails after public metadata
- **WHEN** the public record is written but Keychain storage fails
- **THEN** the system removes the new record or its credential reference, restores the wallet selection the failed import replaced, reports failure, and leaves no Keychain secret

#### Scenario: Only wallet selection fails after both writes succeed
- **WHEN** credential storage and reference attachment both succeed but selecting the wallet fails
- **THEN** the import is reported as successful, the wallet is published as credential-backed, and only the selection failure is surfaced

#### Scenario: App stops between public and protected writes
- **WHEN** the app stops after writing a credential reference but before writing its Keychain item
- **THEN** the next load detaches the missing reference and treats the wallet as watch-only

### Requirement: Credential deletion is authenticated and secret-first
The system SHALL require device-owner authentication for credential-backed deletion, SHALL remove the Keychain item before removing public wallet metadata, and SHALL leave no orphaned secret if later deletion work fails.

#### Scenario: Credential-backed deletion succeeds
- **WHEN** the user confirms deletion, authenticates successfully, and all deletion steps succeed
- **THEN** the credential, address caches, wallet record, and applicable selection are removed

#### Scenario: Delete authentication fails
- **WHEN** the user cancels or fails device-owner authentication
- **THEN** the credential, wallet record, selection, and visible wallet remain unchanged

#### Scenario: Public deletion fails after credential removal
- **WHEN** the Keychain item is removed but cache or wallet-record deletion later fails
- **THEN** the wallet remains visible as watch-only, portfolio loading resumes as needed, a recoverable error is shown, and a re-import alert names the wallet so the destroyed credential is not reported as an unchanged wallet

#### Scenario: Watch-only deletion
- **WHEN** the user confirms deletion of a watch-only wallet
- **THEN** the existing cache and public-record deletion flow runs without device-owner authentication

### Requirement: Missing credentials downgrade safely
The system SHALL check referenced credential presence without presenting authentication UI during wallet load and SHALL detach missing references before publishing the snapshot.

#### Scenario: Referenced credential is present but locked
- **WHEN** non-interactive inspection finds an item that requires user interaction to read
- **THEN** the wallet remains credential-backed and no authentication prompt is shown during load

#### Scenario: Referenced credential is missing
- **WHEN** non-interactive inspection reports that a referenced Keychain item no longer exists
- **THEN** the system preserves the wallet as watch-only and presents a recoverable re-import alert naming the wallet but no secret source

#### Scenario: Credential status cannot be determined
- **WHEN** Keychain inspection fails for a reason other than absence or required interaction
- **THEN** wallet loading reports an error rather than silently changing ownership status

#### Scenario: Inspection fails after earlier wallets were downgraded
- **WHEN** inspection fails for one wallet after earlier wallets in the same load were already detached
- **THEN** the published wallets and re-import alert reflect the detachments that were persisted, so published state never disagrees with the store

### Requirement: Transient secret lifetime is minimized
The system MUST keep submitted secret text only in the active import form and MUST clear it when the user changes method, cancels, completes import, or the app leaves the foreground.

#### Scenario: User pastes a secret
- **WHEN** a user pastes a recovery phrase or private key
- **THEN** the secure input accepts the paste without offering an app-provided copy or export action

#### Scenario: Import form loses its active lifetime
- **WHEN** the import succeeds, is cancelled, changes import method, or leaves the foreground
- **THEN** the form clears its secret text and any retained prepared credential value
