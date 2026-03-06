import AppKit

enum GitLineStatus {
    case unchanged
    case added
    case modified
    case deleted
}

final class GutterView: NSView {
    static let gutterWidth: CGFloat = 52

    var lineCount: Int = 1 { didSet { needsDisplay = true } }
    var font: NSFont = .monospacedSystemFont(ofSize: 14, weight: .regular)
    var textColor: NSColor = .secondaryLabelColor
    var backgroundColor: NSColor = .controlBackgroundColor
    var gitStatuses: [Int: GitLineStatus] = [:] { didSet { needsDisplay = true } }

    // Provided by the text view's layout manager for accurate positioning
    var lineRects: [(lineNumber: Int, rect: NSRect)] = [] { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        canDrawSubviewsIntoLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        canDrawSubviewsIntoLayer = true
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        backgroundColor.setFill()
        dirtyRect.fill()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: font.pointSize - 2, weight: .regular),
            .foregroundColor: textColor
        ]

        for (lineNumber, rect) in lineRects {
            // Draw git indicator
            let status = gitStatuses[lineNumber] ?? .unchanged
            drawGitIndicator(status: status, in: rect)

            // Draw line number
            let numStr = "\(lineNumber)" as NSString
            let size = numStr.size(withAttributes: attrs)
            let x = GutterView.gutterWidth - size.width - 12
            let y = rect.origin.y + (rect.height - size.height) / 2
            numStr.draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
        }
    }

    private func drawGitIndicator(status: GitLineStatus, in rect: NSRect) {
        let indicatorWidth: CGFloat = 3
        let indicatorRect = NSRect(
            x: GutterView.gutterWidth - indicatorWidth - 2,
            y: rect.origin.y + 1,
            width: indicatorWidth,
            height: rect.height - 2
        )

        switch status {
        case .unchanged:
            break
        case .added:
            NSColor.systemGreen.setFill()
            NSBezierPath(roundedRect: indicatorRect, xRadius: 1, yRadius: 1).fill()
        case .modified:
            NSColor.systemBlue.setFill()
            NSBezierPath(roundedRect: indicatorRect, xRadius: 1, yRadius: 1).fill()
        case .deleted:
            let triangleRect = NSRect(
                x: GutterView.gutterWidth - 8,
                y: rect.origin.y,
                width: 6,
                height: 6
            )
            NSColor.systemRed.setFill()
            let path = NSBezierPath()
            path.move(to: NSPoint(x: triangleRect.minX, y: triangleRect.minY))
            path.line(to: NSPoint(x: triangleRect.maxX, y: triangleRect.midY))
            path.line(to: NSPoint(x: triangleRect.minX, y: triangleRect.maxY))
            path.close()
            path.fill()
        }
    }
}
