import Foundation
import Testing
@testable import sevenwallet

struct PullRefreshCoordinatorTests {
    @Test
    func thirdPullForcesAndResets() {
        var value = PullRefreshCoordinator()
        let start = Date(timeIntervalSince1970: 1_000)

        #expect(value.recordPull(at: start) == .ifExpired)
        #expect(value.recordPull(at: start.addingTimeInterval(20)) == .ifExpired)
        #expect(value.recordPull(at: start.addingTimeInterval(59)) == .force)
        #expect(value.recordPull(at: start.addingTimeInterval(60)) == .ifExpired)
    }

    @Test
    func pullsOlderThanWindowDoNotAccumulate() {
        var value = PullRefreshCoordinator()
        let start = Date(timeIntervalSince1970: 1_000)

        #expect(value.recordPull(at: start) == .ifExpired)
        #expect(value.recordPull(at: start.addingTimeInterval(61)) == .ifExpired)
        #expect(value.recordPull(at: start.addingTimeInterval(122)) == .ifExpired)
    }
}
