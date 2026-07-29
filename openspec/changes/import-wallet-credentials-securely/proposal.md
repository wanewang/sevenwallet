## Why

The app can currently save only public Ethereum addresses, so it cannot recognize a wallet as user-controlled or retain the credential needed for future authenticated operations. Users need to import an existing recovery phrase or private key without exposing that secret through SwiftData, logs, backups, or UI after submission.

## What Changes

- Add recovery-phrase and private-key methods to the existing wallet import flow while preserving watch-only address import.
- Validate English 12/24-word BIP-39 recovery phrases and 32-byte Ethereum private keys, derive the first Ethereum account, and show its address before import.
- Store credential bytes in device-only Keychain items protected by device-owner authentication; keep only public wallet metadata and a credential reference in SwiftData.
- Require an explicit backup warning and device authentication for credential import and deletion, and prevent weaker fallback when device security is unavailable.
- Upgrade a matching watch-only wallet only after confirmation, reject duplicate credential-backed imports, and compensate partial Keychain/SwiftData failures without orphaning secrets.
- Preserve a wallet as watch-only and notify the user when its credential becomes unavailable.
- Identify watch-only and imported status in wallet UI without exposing the credential source or adding reveal/export behavior.
- Add a pinned Trust Wallet Core dependency for BIP-39/BIP-44/secp256k1/Ethereum operations.

## Capabilities

### New Capabilities

- `secure-wallet-credentials`: Defines wallet-secret validation and derivation, authenticated device-only storage, import/upgrade/delete coordination, transient secret handling, and credential-loss recovery.
- `wallet-import-methods`: Defines the shared watch-address, recovery-phrase, and private-key import experience and its user-visible validation, confirmation, status, and duplicate behavior.

### Modified Capabilities

- `wallet-list-selection`: Wallet cards and list rows distinguish watch-only wallets from credential-backed imported wallets, and the existing add action opens the expanded import-method flow.

## Impact

- Domain and application layers gain credential state, derivation, secure-storage, and import-coordination interfaces.
- SwiftData saved-wallet records gain non-secret credential metadata while remaining compatible with existing address-only records.
- Add/edit/list/home wallet UI gains import-method, secure-entry, authentication, alert, and ownership-status behavior.
- Wallet deletion coordinates Keychain cleanup with the existing cache and saved-wallet deletion flow.
- The Xcode project adds Security and LocalAuthentication usage plus a version-pinned Trust Wallet Core Swift Package.
- Unit, persistence, view-model, and UI tests gain deterministic public test vectors and protocol-backed secure-storage/authentication doubles; real secrets must never appear in fixtures, logs, or failure text.
