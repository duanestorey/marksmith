import AppKit

enum GitLineStatus {
    case unchanged
    case added
    case modified
    case deleted
}

/// Data container for gutter state. Drawing happens in GutterRulerView.
final class GutterView {
    static let gutterWidth: CGFloat = 52

    var font: NSFont = .monospacedSystemFont(ofSize: 14, weight: .regular)
    var textColor: NSColor = .secondaryLabelColor
    var backgroundColor: NSColor = .controlBackgroundColor
    var gitStatuses: [Int: GitLineStatus] = [:]
    var lineRects: [(lineNumber: Int, rect: NSRect)] = []
}
