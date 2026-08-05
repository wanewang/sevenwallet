import Foundation
import Testing
@testable import sevenwallet

struct WalletCredentialDiagnosticsTests {
    @Test func secretInputsRedactDiagnostics() {
        let phrase = "recovery-phrase-secret-sentinel"
        let privateKey = "private-key-secret-sentinel"

        expectRedacted(
            WalletSecretInput.recoveryPhrase(phrase),
            secretFragments: [phrase]
        )
        expectRedacted(
            WalletSecretInput.privateKey(privateKey),
            secretFragments: [privateKey]
        )
    }

    @Test func credentialPayloadRedactsDiagnostics() {
        let bytes = Data(repeating: 0xA5, count: 32)

        expectRedacted(
            WalletCredentialPayload(kind: .privateKey, bytes: bytes),
            secretFragments: [bytes.base64EncodedString()]
        )
    }

    private func expectRedacted<T>(
        _ value: T,
        secretFragments: [String]
    ) {
        var printed = ""
        print(value, to: &printed)

        var debugPrinted = ""
        debugPrint(value, to: &debugPrinted)

        var dumped = ""
        dump(value, to: &dumped)

        let diagnostics = [
            String(describing: value),
            String(reflecting: value),
            printed,
            debugPrinted,
            dumped
        ]

        #expect(diagnostics.allSatisfy { $0.contains("<redacted>") })
        #expect(Array(Mirror(reflecting: value).children).isEmpty)

        for secret in secretFragments {
            #expect(diagnostics.allSatisfy { !$0.contains(secret) })
        }
    }
}
