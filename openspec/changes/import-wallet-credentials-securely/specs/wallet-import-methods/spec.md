## ADDED Requirements

### Requirement: Add Wallet offers three explicit import methods
The Add Wallet form SHALL offer Watch address, Recovery phrase, and Private key methods while sharing the existing wallet name, card color, Ethereum network, and preview controls.

#### Scenario: Add form opens
- **WHEN** the user opens Add Wallet
- **THEN** the form presents the three import methods and defaults to the existing watch-address behavior

#### Scenario: User changes import method
- **WHEN** the user chooses a different import method
- **THEN** the method-specific input and validation replace the previous input and any secret text from the previous method is cleared

### Requirement: Watch-address import remains supported
The system SHALL preserve address-only import as a watch-only wallet and SHALL keep existing saved wallets with no credential reference usable.

#### Scenario: Import a public address
- **WHEN** the user submits a valid wallet name and Ethereum address through Watch address
- **THEN** the system saves and selects a watch-only wallet without requesting device-owner authentication

#### Scenario: Load an existing address-only record
- **WHEN** a pre-change wallet record is loaded
- **THEN** it remains selectable, editable, deletable, and portfolio-capable as watch-only

### Requirement: Secret methods validate inline and preview the derived address
Recovery phrase and Private key methods SHALL use privacy-sensitive secure input, SHALL present non-secret inline validation, and SHALL show the derived Ethereum address read-only before submission becomes available.

#### Scenario: Recovery phrase receives initial focus
- **WHEN** the user focuses an untouched recovery-phrase field before changing its text
- **THEN** no recovery-phrase validation message appears

#### Scenario: Secret input is invalid
- **WHEN** the user changes a recovery phrase or private key to an invalid value, or attempts submission with invalid secret input
- **THEN** a method-specific validation message appears, no derived address is shown, and import remains disabled

#### Scenario: Secret input is valid
- **WHEN** the entered recovery phrase or private key is valid
- **THEN** the form shows the shortened derived address with the full address as a read-only accessibility value and enables confirmation once the wallet name is also valid

### Requirement: Credential import requires a backup warning
The form SHALL require explicit acknowledgment that the app does not back up, reveal, or export credentials before requesting device-owner authentication and committing a credential-backed import.

#### Scenario: User cancels the import warning
- **WHEN** the user cancels the final credential-import confirmation
- **THEN** the form remains open with no authentication request and no persisted changes

#### Scenario: User accepts the import warning
- **WHEN** the user accepts the final confirmation
- **THEN** the app requests device-owner authentication and proceeds only after it succeeds

### Requirement: Matching watch-only wallets upgrade only after confirmation
When a secret derives an address already saved as watch-only, the system SHALL ask the user to upgrade that wallet in place and SHALL preserve its existing public identity fields.

#### Scenario: Matching watch-only wallet is found
- **WHEN** a valid credential derives the address of an existing watch-only wallet
- **THEN** the confirmation names that wallet and address and offers Upgrade wallet and Cancel actions

#### Scenario: User confirms watch-only upgrade
- **WHEN** the user confirms and authenticated credential storage succeeds
- **THEN** the existing wallet keeps its ID, name, color, creation date, address, caches, and selection identity while becoming credential-backed

#### Scenario: User cancels watch-only upgrade
- **WHEN** the user cancels the upgrade confirmation
- **THEN** the existing wallet remains watch-only and no credential is stored

### Requirement: Credential-backed duplicate imports are rejected
The system SHALL reject a phrase or private key whose derived address already belongs to a credential-backed wallet before authentication or persistence.

#### Scenario: Matching imported wallet is found
- **WHEN** a valid credential derives the address of an existing credential-backed wallet
- **THEN** the form shows a non-secret duplicate message and performs no authentication or writes

### Requirement: Wallet UI communicates ownership without exposing source
The wallet interface SHALL identify watch-only and credential-backed status but SHALL NOT reveal whether an imported credential came from a recovery phrase or private key.

#### Scenario: View a watch-only wallet
- **WHEN** a watch-only wallet appears on the home card, wallet list, or edit form
- **THEN** the interface shows Watch only status

#### Scenario: View a credential-backed wallet
- **WHEN** a credential-backed wallet appears in wallet details or edit mode
- **THEN** the interface shows Imported status without a phrase/private-key label or reveal, copy, and export controls

### Requirement: Successful imports preserve existing wallet behavior
The system SHALL select a newly imported wallet or preserve the upgraded wallet identity, return to wallet home, and load the normalized derived address through the existing portfolio flow.

#### Scenario: New credential import completes
- **WHEN** a new recovery-phrase or private-key import succeeds
- **THEN** the form clears secret input, returns home, and begins the existing cache-first portfolio load for the selected derived address

#### Scenario: Watch-only upgrade completes
- **WHEN** an existing wallet is upgraded successfully
- **THEN** the form clears secret input, returns to that wallet, and does not create a duplicate card

### Requirement: Import failures preserve safe user state
The form SHALL remain usable after validation, authentication, storage, or persistence failure and SHALL display only concise non-secret recovery guidance.

#### Scenario: Credential import fails
- **WHEN** a credential import fails without committing a credential-backed wallet
- **THEN** the form remains open, stops progress state, preserves non-secret form choices, and shows an error that contains no submitted secret

#### Scenario: App leaves the foreground during entry
- **WHEN** the app becomes inactive or enters the background while secret text is present
- **THEN** the secret field is cleared and import must be re-entered before submission
