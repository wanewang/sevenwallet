import Foundation
import Testing
@testable import sevenwallet

struct AppConfigurationTests {
    @Test func environmentWins() throws {
        let value = try AppConfiguration(
            environment: ["BASE_URL": "https://environment.example/"],
            infoDictionary: ["BASE_URL": "https://bundle.example"]
        )
        #expect(value.baseURL.absoluteString == "https://environment.example")
    }

    @Test func bundleSupportsArchiveInjection() throws {
        let value = try AppConfiguration(
            environment: [:],
            infoDictionary: ["BASE_URL": "https://archive.example"]
        )
        #expect(value.baseURL.absoluteString == "https://archive.example")
    }

    @Test(arguments: ["", "wallet.example", "ftp://wallet.example", "https://wallet.example/path", "https://wallet.example?x=1", "https://wallet.example#x"])
    func invalidOriginsFail(_ raw: String) {
        #expect(throws: AppConfiguration.Error.self) {
            try AppConfiguration(environment: ["BASE_URL": raw], infoDictionary: [:])
        }
    }

    @Test func missingOriginIsTyped() {
        #expect(throws: AppConfiguration.Error.missingBaseURL) {
            try AppConfiguration(environment: [:], infoDictionary: [:])
        }
    }
}
