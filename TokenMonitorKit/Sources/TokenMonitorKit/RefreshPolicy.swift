import Foundation

public struct RefreshPolicy: Sendable {
    public let baseInterval: TimeInterval
    public let maxInterval: TimeInterval

    public init(baseInterval: TimeInterval, maxInterval: TimeInterval = 600) {
        self.baseInterval = baseInterval
        self.maxInterval = maxInterval
    }

    public func nextDelay(consecutiveFailures: Int) -> TimeInterval {
        min(baseInterval * pow(2, Double(consecutiveFailures)), maxInterval)
    }
}
