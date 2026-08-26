// App/Tests/SmokeTests.swift
import Testing
@testable import TokenMonitor

@Suite struct SmokeTests {
    @Test func appTypesExist() {
        _ = StatusItemController.self
    }
}
