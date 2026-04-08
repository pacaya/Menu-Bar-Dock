//
//  BadgeRenderer.swift
//  Menu Bar Dock
//

import Cocoa

enum BadgeRenderer {
    /// Returns a new NSImage of size `iconSize × iconSize` with `badge`
    /// drawn as a red pill in the top-right corner. If `badge` is nil or
    /// empty, returns `icon` unchanged.
    static func compose(icon: NSImage, badge: String?, iconSize: CGFloat) -> NSImage {
        guard let badge = badge, !badge.isEmpty else {
            return icon
        }

        let displayText = badge.count > 3 ? "99+" : badge
        let result = NSImage(size: NSSize(width: iconSize, height: iconSize))

        result.lockFocus()
        defer { result.unlockFocus() }

        icon.draw(
            in: NSRect(x: 0, y: 0, width: iconSize, height: iconSize),
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0
        )

        let badgeRect = pillRect(for: displayText, iconSize: iconSize)
        drawPill(in: badgeRect)
        drawText(displayText, in: badgeRect)

        return result
    }

    private static func pillRect(for text: String, iconSize: CGFloat) -> NSRect {
        let badgeHeight = max(12, iconSize * 0.45)
        let charCount = CGFloat(text.count)
        let badgeWidth = badgeHeight + max(0, (charCount - 1)) * badgeHeight * 0.55
        let inset: CGFloat = 1
        // NSImage origin is bottom-left, so "top-right" uses high y.
        return NSRect(
            x: iconSize - badgeWidth - inset,
            y: iconSize - badgeHeight - inset,
            width: badgeWidth,
            height: badgeHeight
        )
    }

    private static func drawPill(in rect: NSRect) {
        let pill = NSBezierPath(
            roundedRect: rect,
            xRadius: rect.height / 2,
            yRadius: rect.height / 2
        )
        NSColor.systemRed.setFill()
        pill.fill()
        NSColor.white.setStroke()
        pill.lineWidth = 1
        pill.stroke()
    }

    private static func drawText(_ text: String, in rect: NSRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: rect.height * 0.62, weight: .bold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph
        ]
        let attrString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attrString.size()
        let textRect = NSRect(
            x: rect.minX,
            y: rect.minY + (rect.height - textSize.height) / 2,
            width: rect.width,
            height: textSize.height
        )
        attrString.draw(in: textRect)
    }
}
