## Context

`SavedWallet` and `SavedWalletStore` currently persist public Ethereum identity in SwiftData, while `WalletSession` coordinates mutations, cache cleanup, selection, and portfolio loading. `WalletFormViewModel` accepts only a public address. The project has no cryptographic or Keychain dependency.

Imported recovery phrases and private keys introduce a separate trust domain: secret material must be validated and used to derive an address, but it must not become part of the existing Codable/SwiftData models, logs, error text, clipboard output, backups, or observable state. Keychain and SwiftData cannot share a transaction, so import, upgrade, and deletion also need explicit crash and failure semantics.

## Goals / Non-Goals

**Goals:**

- Preserve the current watch-only workflow while importing English 12/24-word BIP-39 phrases and 32-byte Ethereum private keys.
- Derive only Ethereum account `m/44'/60'/0'/0/0` with an empty BIP-39 passphrase.
- Put cryptographic parsing/derivation and protected storage behind small, testable interfaces.
- Store mnemonic entropy or private-key bytes only in non-synchronizing, device-only Keychain items guarded by device-owner authentication.
- Keep public identity usable and accurately labeled if its credential disappears.
- Make cross-store mutations converge without leaving an unreferenced secret.

**Non-Goals:**

- Generating wallets, supporting an additional BIP-39 passphrase, other languages/word counts, account/path selection, or non-Ethereum networks.
- Revealing, copying, exporting, backing up, signing with, or sending transactions from stored credentials.
- Changing portfolio networking or adding cloud credential synchronization.

## Decisions

### A credential is an optional reference on the public wallet

`SavedWallet` gains an optional `WalletCredentialReference` value. `nil` means watch-only; a reference means imported. `SavedWalletRecord` stores only the reference UUID, never credential kind or bytes. Existing records migrate naturally to `nil`, and UI derives ownership status from this value without revealing whether the source was a phrase or key.

Using an optional reference instead of a separate parallel wallet type keeps selection, portfolio, naming, coloring, and address identity unchanged. Storing encrypted blobs in SwiftData was rejected because it expands backup and database exposure. Storing the credential source in public metadata was rejected because callers do not need it.

### Cryptography sits behind one derivation seam

`WalletCredentialDeriving` accepts a typed phrase/private-key input and returns a `PreparedWalletCredential` containing the normalized Ethereum address plus an opaque, non-Codable credential payload. The production adapter uses Trust Wallet Core from its official remote Swift Package repository. The project accepts version 4.7.1 up to the next major release, while the committed package resolution locks the current checkout to 4.7.1:

- Phrase input is Unicode-normalized, lowercased, split on whitespace, restricted to 12 or 24 English words, and validated by Wallet Core. `HDWallet.entropy` becomes the stored payload. The address comes from the private key at `m/44'/60'/0'/0/0` with an empty BIP-39 passphrase.
- Private-key input trims surrounding whitespace and an optional `0x`, decodes exactly 32 bytes, validates the secp256k1 scalar through Wallet Core, and derives the Ethereum address.

The form uses this interface for validation/address preview and recomputes a short-lived prepared value on submission rather than retaining credential bytes in observable state. A credential field becomes interacted only when its submitted text value actually changes, matching the watch-address field; initial focus alone does not reveal validation. An invalid submission still reveals the relevant validation message. A deterministic adapter exercises callers in tests; integration tests at the derivation interface use published BIP-39 and private-key vectors. Implementing BIP-39/BIP-32/secp256k1/Keccak locally was rejected as unnecessary cryptographic risk.

`WalletSecretInput` and `WalletCredentialPayload` expose only `<redacted>` through their string, debug-string, and mirror representations. This prevents generic diagnostic and reflection APIs from traversing the stored phrase, private-key text, or credential bytes.

### Protected storage is a deep module over Security and LocalAuthentication

`WalletCredentialVault` exposes availability, non-interactive presence checking, authenticated store/read, and authenticated delete operations keyed by `WalletCredentialReference`. Its production adapter owns all `Security` and `LocalAuthentication` details; an in-memory adapter is used by application tests.

Each credential is a versioned binary envelope (`version`, `kind`, `bytes`) stored as a generic-password Keychain item under an app-specific service and random reference account. The item uses `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly`, `SecAccessControl` with `.userPresence`, and no synchronizable/access-group setting. This prevents iCloud Keychain sync and backup restore, requires an unlocked passcode-protected device, and authenticates every data read. Explicit `deviceOwnerAuthentication` is also required before store and delete so those mutations cannot occur silently. If protection is unavailable or authentication is cancelled, the operation fails without fallback.

Secure Enclave storage was rejected because imported BIP-39 entropy and arbitrary secp256k1 private keys cannot be generated or represented as Secure Enclave keys. App-level encryption with a UserDefaults/SwiftData key was rejected because it is shallower and weaker than the platform Keychain policy.

### `WalletSession` remains the mutation coordinator

The existing `WalletSession` interface expands with a credential-backed import operation and retains one mutation gate. The UI supplies validated public form values, a freshly prepared credential, and an optional confirmed upgrade wallet ID. The session rechecks the derived address and duplicate state before side effects.

For a new import, the store first writes/selects public metadata containing a fresh credential reference, then the vault stores the secret, and only the completed snapshot is published. If vault storage fails, the store removes the new record; if rollback also fails, the next load reconciles the missing reference to watch-only. Writing the reference first ensures a crash can produce only a recoverable missing credential, never an unreferenced Keychain secret.

For a confirmed watch-only upgrade, the store attaches a fresh reference to the existing record before vault storage. A storage failure detaches it; the current name, color, ID, creation date, address, and caches remain unchanged. An imported duplicate fails before authentication or writes.

For credential-backed deletion, the vault authenticates and removes the Keychain item before `SavedWalletStore` removes public metadata, while the existing session still suspends portfolio loads and purges address caches. If later cache/metadata deletion fails, the session detaches the now-missing reference when possible, keeps the wallet visible as watch-only, resumes loading, and reports the failure. Watch-only deletion keeps the current no-authentication path. This ordering prioritizes never leaving a secret for a wallet that appears deleted.

### Load reconciles credential presence without prompting

After loading the saved snapshot, the session asks the vault for each referenced item's presence with authentication UI disabled. `errSecSuccess` and an interaction-required status mean present; `errSecItemNotFound` means missing. Missing references are detached in SwiftData before the snapshot is published. The session exposes one recoverable alert telling the user the named wallet is now watch-only and must be re-imported. Other Keychain errors fail loading rather than silently downgrading ownership.

This lazy reconciliation also repairs crashes between the public metadata write and Keychain store. Enumerating and deleting all unreferenced Keychain items was rejected because the reference-first write order avoids creating them and broad cleanup risks deleting recoverable data after database errors.

### The form owns transient text and explicit confirmation state

Add mode gains a three-way import method picker. Watch address retains the current text field and validation. Phrase/private-key methods use secure multiline/single-line inputs with paste enabled, copy/export actions disabled where platform controls allow, autocorrection/capitalization disabled, and `.privacySensitive()` presentation. Valid input shows a read-only derived address.

Submission first presents one confirmation containing the no-backup/no-export warning. For an address matching a watch-only wallet, that confirmation also names the existing wallet/address and says it will be upgraded; cancel performs no mutation. After confirmation, device authentication and coordinated import run. A credential-backed duplicate shows a non-secret error and never prompts. The form clears secret text on cancel, successful import, method change, and transition out of the active scene. Swift `String` storage cannot guarantee zeroization of all copies, so lifetime minimization and exclusion from persistence/logging are the practical mitigation.

Edit mode shows Imported or Watch only status but offers no credential reveal or source detail. Credential-backed deletion uses the existing destructive confirmation followed by authenticated deletion.

### Wallet navigation reuses one back-button module

A shared `WalletBackButton` SwiftUI view provides the back-navigation interface: theme, action, disabled state, and accessibility identifier. Its implementation delegates presentation to a general `WalletActionButtonStyle`, which owns the common 44-point square frame, rounded-rectangle shape, pressed feedback, and configurable foreground, background, and optional border colors. The back button applies the Wallet List's neutral treatment, while the Wallet List add button applies its existing accent treatment through the same style.

The Add Wallet and Wallet List headers both use the shared back-button module instead of duplicating button markup. Add Wallet retains its cancel-and-clear action and disabled-while-submitting behavior, while Wallet List retains its existing action and accessibility identifier. Reusing the general style for both back and add actions keeps presentation local without expanding the back-button interface with unrelated header concerns.

## Risks / Trade-offs

- **[Swift strings cannot guarantee zeroization]** → Keep secret text only in form state, clear it on every exit/background path, never interpolate it into diagnostics, and keep derived payloads non-Codable/non-printable.
- **[Keychain and SwiftData are not transactional]** → Write public references before secrets, use compensating removal/detach operations, publish only completed snapshots, and reconcile missing references on load.
- **[Passcode removal invalidates device-only items]** → Preserve and relabel the wallet as watch-only, alert once, and support the confirmed re-import upgrade path.
- **[Authentication prompts complicate automated tests]** → Test application behavior through protocol adapters and keep a small simulator-only integration suite for Keychain status mapping; never weaken production access flags for tests.
- **[Remote binary dependency increases app size and supply-chain surface]** → Commit the Wallet Core 4.7.1 package resolution, restrict its use to the derivation adapter, and verify known vectors.
- **[Only account zero is imported]** → State the derivation path in supporting UI and specs; account discovery is a later change.

## Migration Plan

1. Add the optional credential-reference field so existing SwiftData records decode as watch-only.
2. Ship the derivation and vault adapters plus application coordination before exposing secret inputs.
3. Enable the expanded import form and ownership labels after migration/reconciliation paths are covered by tests.
4. On rollback, older app code ignores the optional credential metadata but Keychain items may remain. Therefore a production rollback must retain a small credential-cleanup migration or ship forward with the model/UI disabled; simply installing an older build is not a safe secret-deletion strategy.

## Open Questions

None. Transaction signing, additional accounts, additional BIP-39 passphrases, and credential export require separate changes.
