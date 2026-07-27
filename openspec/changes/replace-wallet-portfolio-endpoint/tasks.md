## 1. Endpoint Integration

- [x] 1.1 Replace the portfolio endpoint path with `/v1/wallet/{address}` while preserving normalized-address construction and the existing endpoint case.
- [x] 1.2 Update API-client request coverage to require the new wallet path while retaining existing portfolio decoding assertions.

## 2. Verification

- [x] 2.1 Run the focused `APIClientTests` suite and confirm the wallet request and nullable metadata behavior pass.
- [x] 2.2 Run the full `sevenwalletTests` target and `git diff --check` to verify no regressions or whitespace errors.
