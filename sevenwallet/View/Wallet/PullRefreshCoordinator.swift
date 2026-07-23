import Foundation

struct PullRefreshCoordinator {
    private var pulls: [Date] = []

    mutating func recordPull(at date: Date) -> RefreshPolicy {
        pulls.removeAll { date.timeIntervalSince($0) > 60 }
        pulls.append(date)
        guard pulls.count >= 3 else { return .ifExpired }
        pulls.removeAll(keepingCapacity: true)
        return .force
    }
}
