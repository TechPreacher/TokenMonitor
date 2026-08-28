// App/Sources/StatusItemController.swift
import AppKit
import SwiftUI

@MainActor
final class StatusItemController: NSObject, NSWindowDelegate {
    private let statusItem: NSStatusItem
    private var panel: FloatingPanel?
    private var clickMonitor: Any?
    private let viewModel = DashboardViewModel.live()

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "gauge.with.dots.needle.67percent",
                                   accessibilityDescription: "TokenMonitor")
            button.action = #selector(handleClick)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func handleClick() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePanel()
        }
    }

    private func togglePanel() {
        if let panel, panel.isVisible {
            closePanel()
        } else {
            openPanel()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "About TokenMonitor",
                                action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit TokenMonitor",
                              action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        menu.items.first?.target = self
        // Assign transiently so left-click keeps toggling the panel instead of opening the menu.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    private func openPanel() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        positionUnderStatusItem(panel)
        panel.orderFrontRegardless()
        installOutsideClickMonitor()
        // Opening the panel is the user's "check now" gesture — don't make
        // them wait for the next polling tick to see fresh session data.
        Task { [viewModel] in await viewModel.refreshLocalSources() }
    }

    private func closePanel() {
        panel?.orderOut(nil)
        removeOutsideClickMonitor()
    }

    private func makePanel() -> FloatingPanel {
        let panel = FloatingPanel(content: DashboardView(viewModel: viewModel) { [weak self] pinned in
            self?.panel?.isPinned = pinned
        })
        viewModel.startPolling()
        return panel
    }

    private func positionUnderStatusItem(_ panel: NSPanel) {
        guard let buttonWindow = statusItem.button?.window else { return }
        panel.layoutIfNeeded()   // content-driven height must be final before anchoring
        let buttonFrame = buttonWindow.frame
        // swiftlint:disable:next identifier_name
        var x = buttonFrame.midX - panel.frame.width / 2
        // swiftlint:disable:next identifier_name
        var y = buttonFrame.minY - panel.frame.height - 4
        // Menu-bar managers (Ice/Bartender) park hidden status items offscreen;
        // clamp so the panel always lands on the visible screen.
        // Offscreen-parked windows report screen == nil, and NSScreen.main is
        // also nil while this non-activating app has no key window.
        let screen = buttonWindow.screen ?? NSScreen.main ?? NSScreen.screens.first
        if let visible = screen?.visibleFrame {
            x = min(max(x, visible.minX + 8), visible.maxX - panel.frame.width - 8)
            y = min(max(y, visible.minY + 8), visible.maxY - panel.frame.height - 8)
        }
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func installOutsideClickMonitor() {
        removeOutsideClickMonitor()
        clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, let panel = self.panel, !panel.isPinned else { return }
            self.closePanel()
        }
    }

    private func removeOutsideClickMonitor() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }
}
