## 1. Dependency and Credential Domain

- [x] 1.1 Add the official remote Trust Wallet Core Swift Package dependency, commit its 4.7.1 package resolution, and verify both binary products resolve and build for the app/test targets.
- [x] 1.2 Add typed import-method, credential-reference, opaque credential-payload, preparation-result, and non-secret error domain values without Codable, printable, or logging exposure for secret bytes.
- [x] 1.3 Write derivation-interface tests for normalization, valid/invalid 12/24-word BIP-39 input, strict private-key parsing, scalar rejection, and published Ethereum address vectors.
- [x] 1.4 Implement the Trust Wallet Core derivation adapter for mnemonic entropy and `m/44'/60'/0'/0/0` or raw-key Ethereum address derivation until the vector tests pass.

## 2. Authenticated Credential Vault

- [x] 2.1 Write tests for a versioned binary credential envelope that round-trips 128/256-bit mnemonic entropy and 32-byte private keys while rejecting unknown versions, kinds, and lengths.
- [x] 2.2 Define the protected-vault interface and in-memory test adapter for protection availability, non-interactive presence, authenticated store/read, and authenticated delete outcomes.
- [x] 2.3 Implement the Security/LocalAuthentication vault adapter using `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly`, `.userPresence`, disabled synchronization, opaque references, non-secret errors, and no weaker fallback.
- [x] 2.4 Add focused tests for Keychain status mapping, unavailable device protection, authentication cancellation/failure, duplicate items, missing items, and absence of secret material from errors.

## 3. Public Wallet Persistence

- [x] 3.1 Write persistence migration/round-trip tests proving existing records load watch-only and imported records store only an optional opaque credential reference.
- [x] 3.2 Extend `SavedWallet`, `SavedWalletRecord`, snapshots, and store mapping with optional credential references while keeping existing identity equality/order behavior.
- [x] 3.3 Write and implement atomic store operations to attach/detach a credential reference and to roll back a newly added credential-backed record without changing unrelated wallets or selection.

## 4. Credential Lifecycle Coordination

- [x] 4.1 Write session tests for load-time non-interactive credential reconciliation, missing-item downgrade/alert, locked-item preservation, and indeterminate-status load failure.
- [x] 4.2 Implement load reconciliation and a recoverable, non-secret re-import alert before publishing the wallet snapshot.
- [x] 4.3 Write session tests for new credential import success, unavailable protection, authentication cancellation, public-write failure, vault-write failure, rollback failure, selection, and portfolio-load behavior.
- [x] 4.4 Implement reference-first new credential import with one mutation gate, authenticated vault storage, compensating public rollback, and completed-snapshot publication.
- [x] 4.5 Write session tests for matching watch-only upgrade confirmation/recheck, identity preservation, imported duplicate rejection before authentication, vault failure detach, and no duplicate wallet.
- [x] 4.6 Implement confirmed in-place watch-only upgrade and duplicate enforcement.
- [x] 4.7 Write session tests for authenticated credential deletion, authentication cancellation, secret-first ordering, later cache/metadata failure downgrade, and unchanged watch-only deletion.
- [x] 4.8 Implement credential-backed deletion while preserving portfolio suspension/resume, cache cleanup, selection, and safe failure state.

## 5. Import and Ownership User Experience

- [x] 5.1 Write form-view-model tests for the three methods, method-specific validation, derived-address preview, duplicate classification, non-secret errors, and secret clearing on method change/cancel/success/inactive scene.
- [x] 5.2 Extend the form view model to use the derivation interface without retaining prepared credential bytes in observable state and to require confirmation before credential submission.
- [x] 5.3 Implement the import-method picker, privacy-sensitive phrase/private-key fields with paste support, inline validation, derived-address preview, backup/upgrade confirmations, and device-protection/authentication errors.
- [x] 5.4 Add Watch only and Imported status to home, list, and edit surfaces without exposing credential source or reveal/copy/export controls.
- [x] 5.5 Update deletion UI so credential-backed wallets retain destructive confirmation and then authenticate, while watch-only deletion remains unchanged.

## 6. Verification

- [x] 6.1 Add/update UI tests for watch-only import, phrase/private-key validation and preview, warning cancellation, watch-only upgrade alert, duplicate rejection, ownership labels, secret clearing, and authenticated-path test adapters.
- [x] 6.2 Run all unit tests on an iOS simulator and fix failures without weakening security assertions.
- [x] 6.3 Run the UI test suite, simulator build with code signing disabled, OpenSpec validation, and `git diff --check`; audit every agreed scenario against test or runtime evidence.

## 7. Validation Timing and Shared Header Actions

- [x] 7.1 Add a UI regression test proving that first focus on an untouched Recovery phrase field does not show a validation error.
- [x] 7.2 Update secret-input interaction tracking so a field becomes interacted only when its text changes, while invalid submission still reveals validation.
- [x] 7.3 Add a general `WalletActionButtonStyle` and shared `WalletBackButton`, reuse the back button in Add Wallet and Wallet List, and reuse the general style for Wallet List's add action.
- [x] 7.4 Run the focused UI regression, simulator tests and build, OpenSpec validation, and `git diff --check`.

## 8. Review Remediation

- [x] 8.1 Reject non-hex private-key input by validating UTF-8 bytes directly, closing both the `+`/`-` sign-prefix acceptance and the Character/UTF-8 index mismatch that trapped on multibyte input.
- [x] 8.2 Compile the plaintext fixture credential vault and its selection branch out of release builds.
- [x] 8.3 Publish credential downgrades already persisted when a later presence check fails, and report the specific credential error.
- [x] 8.4 Raise the re-import alert when a credential-backed deletion fails after the secret was destroyed.
- [x] 8.5 Report a derivation failure during credential submission instead of returning silently.
- [x] 8.6 Restore the replaced wallet selection when a credential-backed add is rolled back.
- [x] 8.7 Treat an upgrade's selection failure as a successful import with a selection error.
- [x] 8.8 Give Keychain read and delete failures their own errors instead of reusing the storage-failure message.
- [x] 8.9 Cover Keychain query construction and the vault store success path, asserting the encoded envelope, the account, and the access-control attributes.
- [x] 8.10 Run the unit and UI suites, a release build, and OpenSpec validation.
