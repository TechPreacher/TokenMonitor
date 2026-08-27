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
        let hosting = NSHostingView(rootView: content)
        hosting.sizingOptions = [.preferredContentSize]
        contentView = hosting
        isPinned = false
    }

    override var canBecomeKey: Bool { true }

    /// Content-driven height changes keep the top edge anchored under the
    /// status item, so the panel grows/shrinks downward.
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var rect = frameRect
        if isVisible && abs(frameRect.height - frame.height) > 0.5 {
            rect.origin.y = frame.maxY - frameRect.height
        }
        super.setFrame(rect, display: flag)
    }
}
