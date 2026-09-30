import AppKit

enum PanelPositioner {
    static let defaultSize = NSSize(width: 460, height: 380)

    /// Places the panel according to the user's chosen placement setting,
    /// clamped to the visible area of the active screen. When `sizeOverride`
    /// is non-nil (e.g. a per-preset size), it wins over the panel's
    /// current frame size.
    static func position(
        panel: NSPanel,
        placement: SettingsStore.PanelPlacement,
        sizeOverride: NSSize? = nil
    ) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
            ?? NSScreen.main
        guard let screen else { return }

        let size: NSSize
        if let override = sizeOverride {
            size = override
        } else if panel.frame.size == .zero {
            size = defaultSize
        } else {
            size = panel.frame.size
        }
        let origin: NSPoint

        switch placement {
        case .nearMouse:
            origin = NSPoint(x: mouse.x + 12, y: mouse.y - size.height - 12)
        case .centeredOnCursor:
            origin = NSPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height / 2)
        case .centeredOnScreen:
            let f = screen.visibleFrame
            origin = NSPoint(x: f.midX - size.width / 2, y: f.midY - size.height / 2)
        }

        panel.setFrame(NSRect(origin: clamp(origin: origin, size: size, into: screen.visibleFrame),
                              size: size),
                       display: true)
    }

    private static func clamp(origin: NSPoint, size: NSSize, into visible: NSRect) -> NSPoint {
        var o = origin
        if o.x + size.width > visible.maxX { o.x = visible.maxX - size.width - 12 }
        if o.x < visible.minX { o.x = visible.minX + 12 }
        if o.y + size.height > visible.maxY { o.y = visible.maxY - size.height - 12 }
        if o.y < visible.minY { o.y = visible.minY + 12 }
        return o
    }
}
