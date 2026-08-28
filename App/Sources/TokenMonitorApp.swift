// App/Sources/TokenMonitorApp.swift
import SwiftUI
import TokenMonitorKit

@main
struct TokenMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No WindowGroup — LSUIElement app; UI lives in the NSPanel.
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusItemController?
    private var activity: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Opt out of App Nap: as a background LSUIElement app the 30s/60s
        // polling timers get throttled to minutes when the panel is closed,
        // which made the app miss new sessions until long after they started.
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated],
            reason: "Continuous Claude Code usage monitoring")
        statusController = StatusItemController()
    }
}
