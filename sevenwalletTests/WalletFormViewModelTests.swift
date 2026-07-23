import Foundation
import Testing
@testable import sevenwallet

@MainActor
struct WalletFormViewModelTests {
    @Test func addRequiresValidNameAndAddress() {
        let form = WalletFormViewModel(mode: .add)
        form.setName("Main")
        form.address = "0x1234"
        #expect(!form.canSubmit)
        #expect(form.addressError == nil)

        form.didInteractWithAddress = true
        #expect(form.addressError == "Enter a valid Ethereum address.")

        form.address = "0x71A2B3C4D5E6F7890A1B2C3D4E5F67890ABC8F92"
        #expect(form.canSubmit)
        #expect(form.primaryActionTitle == "Add wallet")
    }

    @Test func nameInputCapsAtTwentyCharacters() {
        let form = WalletFormViewModel(mode: .add)

        form.setName("12345678901234567890x")

        #expect(form.name == "12345678901234567890")
    }

    @Test func editPrefillsAndLocksAddress() throws {
        let wallet = try makeWallet(name: "Main", cardColor: .teal)
        let form = WalletFormViewModel(mode: .edit(wallet))

        #expect(form.title == "Edit wallet")
        #expect(form.primaryActionTitle == "Save changes")
        #expect(form.name == "Main")
        #expect(form.address == wallet.address.rawValue)
        #expect(!form.isAddressEditable)
        #expect(form.showsDelete)
    }

    @Test func failedSavePreservesInputAndShowsError() async throws {
        let store = ScriptedSavedWalletStore()
        await store.setError(RepositoryTestError.remoteFailure)
        let session = WalletSession(
            store: store,
            cachePurger: RecordingAddressCachePurger()
        )
        let form = WalletFormViewModel(mode: .add)
        form.setName("Main")
        form.address = "0x71A2B3C4D5E6F7890A1B2C3D4E5F67890ABC8F92"

        #expect(await form.submit(session: session) == false)
        #expect(form.name == "Main")
        #expect(form.submissionError == "Unable to save wallet.")
        #expect(!form.isSubmitting)
    }

    @Test func addNormalizesNameAndAddressBeforeSaving() async throws {
        let store = ScriptedSavedWalletStore()
        let session = WalletSession(
            store: store,
            cachePurger: RecordingAddressCachePurger()
        )
        let form = WalletFormViewModel(mode: .add)
        form.setName("  Main  ")
        form.address = "  0x71A2B3C4D5E6F7890A1B2C3D4E5F67890ABC8F92  "

        #expect(await form.submit(session: session))
        #expect(session.selectedWallet?.name == "Main")
        #expect(session.selectedWallet?.address.rawValue == "0x71a2b3c4d5e6f7890a1b2c3d4e5f67890abc8f92")
    }

    @Test func editOnlySavesNameAndColor() async throws {
        let wallet = try makeWallet(name: "Main", cardColor: .blue)
        let store = ScriptedSavedWalletStore(
            snapshot: .init(wallets: [wallet], selectedWalletID: wallet.id)
        )
        let session = WalletSession(
            store: store,
            cachePurger: RecordingAddressCachePurger()
        )
        await session.load()
        let form = WalletFormViewModel(mode: .edit(wallet))
        form.setName("Renamed")
        form.selectedColor = .pink
        form.address = "0x0000000000000000000000000000000000000000"

        #expect(await form.submit(session: session))
        #expect(session.selectedWallet?.name == "Renamed")
        #expect(session.selectedWallet?.cardColor == .pink)
        #expect(session.selectedWallet?.address == wallet.address)
    }

    @Test func failedDeletePreservesInputAndShowsError() async throws {
        let wallet = try makeWallet(name: "Main", cardColor: .blue)
        let store = ScriptedSavedWalletStore(
            snapshot: .init(wallets: [wallet], selectedWalletID: wallet.id)
        )
        let session = WalletSession(
            store: store,
            cachePurger: RecordingAddressCachePurger()
        )
        await session.load()
        await store.setError(RepositoryTestError.remoteFailure)
        let form = WalletFormViewModel(mode: .edit(wallet))
        form.setName("Renamed")

        #expect(await form.delete(session: session) == false)
        #expect(form.name == "Renamed")
        #expect(form.submissionError == "Unable to delete wallet.")
        #expect(!form.isSubmitting)
    }

    @Test func addModeCannotDelete() async {
        let session = WalletSession(
            store: ScriptedSavedWalletStore(),
            cachePurger: RecordingAddressCachePurger()
        )
        let form = WalletFormViewModel(mode: .add)

        #expect(await form.delete(session: session) == false)
        #expect(!form.isSubmitting)
    }

    @Test func duplicateSubmissionsDoNotSaveTwice() async {
        let store = GatedSavedWalletStore()
        let session = WalletSession(
            store: store,
            cachePurger: RecordingAddressCachePurger()
        )
        let form = WalletFormViewModel(mode: .add)
        form.setName("Main")
        form.address = "0x71A2B3C4D5E6F7890A1B2C3D4E5F67890ABC8F92"

        let first = Task { @MainActor in
            await form.submit(session: session)
        }
        await store.waitUntilAddStarted()

        #expect(await form.submit(session: session) == false)
        #expect(await store.addCallCount == 1)

        await store.releaseAdd()
        #expect(await first.value)
    }

    private func makeWallet(
        name: String,
        cardColor: WalletCardColor
    ) throws -> SavedWallet {
        SavedWallet(
            name: name,
            address: try EVMAddress(
                "0x71A2B3C4D5E6F7890A1B2C3D4E5F67890ABC8F92"
            ),
            cardColor: cardColor
        )
    }

    private actor GatedSavedWalletStore: SavedWalletStoreProtocol {
        private var addStarted = false
        private var addStartedContinuation: CheckedContinuation<Void, Never>?
        private var releaseAddContinuation: CheckedContinuation<Void, Never>?
        private(set) var addCallCount = 0

        func loadSnapshot() async throws -> SavedWalletSnapshot {
            .init(wallets: [], selectedWalletID: nil)
        }

        func addAndSelect(_ wallet: SavedWallet) async throws -> SavedWalletSnapshot {
            addCallCount += 1
            addStarted = true
            addStartedContinuation?.resume()
            addStartedContinuation = nil
            await withCheckedContinuation { continuation in
                releaseAddContinuation = continuation
            }
            return .init(wallets: [wallet], selectedWalletID: wallet.id)
        }

        func update(
            id: UUID,
            name: String,
            cardColor: WalletCardColor
        ) async throws -> SavedWalletSnapshot {
            .init(wallets: [], selectedWalletID: nil)
        }

        func delete(id: UUID) async throws -> SavedWalletSnapshot {
            .init(wallets: [], selectedWalletID: nil)
        }

        func waitUntilAddStarted() async {
            guard !addStarted else { return }
            await withCheckedContinuation { continuation in
                addStartedContinuation = continuation
            }
        }

        func releaseAdd() {
            releaseAddContinuation?.resume()
            releaseAddContinuation = nil
        }
    }
}
