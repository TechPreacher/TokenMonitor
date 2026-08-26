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
            button.action = #selector(togglePanel)
            button.target = self
        }
    }

    @objc private func togglePanel() {
        if let panel, panel.isVisible {
            closePanel()
        } else {
            openPanel()
        }
    }

    private func openPanel() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        positionUnderStatusItem(panel)
        panel.orderFrontRegardless()
        installOutsideClickMonitor()
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
        let buttonFrame = buttonWindow.frame
        // swiftlint:disable:next identifier_name
        let x = buttonFrame.midX - panel.frame.width / 2
        // swiftlint:disable:next identifier_name
        let y = buttonFrame.minY - panel.frame.height - 4
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
