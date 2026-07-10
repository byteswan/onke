import AppKit
import SwiftUI

/// A borderless, non-activating `NSPanel` that floats above normal windows on every
/// Space without stealing focus (spec §5.2). It hosts an arbitrary SwiftUI root and
/// persists its own origin to UserDefaults so it reappears where the user left it.
final class FloatingPanel<Content: View>: NSPanel {

    private static var originDefaultsKey: String { "panel.origin" }

    init(rootView: Content) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 180),
            // .nonactivatingPanel is what keeps clicks from stealing focus from the
            // frontmost app; .borderless drops the title bar / close box entirely.
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        // Visible on all Spaces, and stays put when the user switches Spaces.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        isMovableByWindowBackground = true       // draggable from anywhere in the body
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        let hosting = NSHostingView(rootView: rootView)
        hosting.autoresizingMask = [.width, .height]
        contentView = hosting

        restoreOrigin()
    }

    /// Panels are ineligible to be key/main by default; opt back in only for key so
    /// controls inside the SwiftUI view remain clickable, while never becoming main
    /// (which would activate the app and steal focus).
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Show without activating the app or making the panel key.
    func present() {
        orderFrontRegardless()
    }

    // MARK: Position persistence

    private func restoreOrigin() {
        if let stored = UserDefaults.standard.string(forKey: Self.originDefaultsKey) {
            let point = NSPointFromString(stored)
            setFrameOrigin(point)
        } else {
            center()
        }
    }

    override func setFrameOrigin(_ point: NSPoint) {
        super.setFrameOrigin(point)
        UserDefaults.standard.set(NSStringFromPoint(point), forKey: Self.originDefaultsKey)
    }
}
