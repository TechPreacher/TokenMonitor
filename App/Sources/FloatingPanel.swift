// App/Sources/FloatingPanel.swift
import AppKit
import SwiftUI

/// Non-activating panel hosting SwiftUI content. Pinned -> floats above all
/// windows and survives app switches; unpinned -> closes on outside click.
final class FloatingPanel: NSPanel {
    var isPinned = false {
        didSet {
            level = isPinned ? .floating : .normal
            hidesOnDeactivate = !isPinned
        }
    }

    init(content: some View) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 320, height: 420),
                   styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
                   backing: .buffered, defer: false)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        backgroundColor = .clear
        isOpaque = false
        contentView = NSHostingView(rootView: content)
        isPinned = false
    }

    override var canBecomeKey: Bool { true }
}
