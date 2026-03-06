import SwiftUI
import AppKit

struct EditorView: NSViewRepresentable {
    @ObservedObject var document: MarkdownDocument
    var theme: EditorTheme
    var gitStatuses: [Int: GitLineStatus]

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.wantsLayer = true
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        let textContainer = NSTextContainer(size: containerSize)
        textContainer.widthTracksTextView = true
        textContainer.lineFragmentPadding = 4
        layoutManager.addTextContainer(textContainer)

        let textView = MarkdownTextView(frame: .zero, textContainer: textContainer)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        textView.textContainerInset = NSSize(width: 4, height: 8)
        textView.applyTheme(theme)

        textView.onTextChange = { [weak textView] newText in
            guard let textView = textView else { return }
            context.coordinator.textDidChange(newText, textView: textView)
        }

        // Set up gutter
        let gutterView = GutterView(frame: NSRect(x: 0, y: 0, width: GutterView.gutterWidth, height: 0))
        gutterView.font = textView.font ?? .monospacedSystemFont(ofSize: 14, weight: .regular)

        let rulerView = GutterRulerView(scrollView: scrollView, orientation: .verticalRuler)
        rulerView.gutterView = gutterView
        rulerView.textView = textView
        rulerView.ruleThickness = GutterView.gutterWidth
        scrollView.verticalRulerView = rulerView
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        scrollView.documentView = textView

        // Set initial text
        textView.string = document.text

        // Set up syntax highlighter
        context.coordinator.setupSyntaxHighlighter(textView: textView, theme: theme)

        // Observe scroll/layout changes to update gutter
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.textViewDidChangeLayout(_:)),
            name: NSView.frameDidChangeNotification,
            object: textView
        )
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.textViewDidChangeLayout(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        context.coordinator.rulerView = rulerView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }

        if textView.string != document.text {
            let selectedRanges = textView.selectedRanges
            textView.string = document.text
            textView.selectedRanges = selectedRanges
            context.coordinator.syntaxHighlighter?.invalidate()
        }

        textView.applyTheme(theme)
        context.coordinator.rulerView?.gutterView?.backgroundColor = theme.backgroundColor.blended(
            withFraction: 0.05, of: .gray) ?? theme.backgroundColor
        context.coordinator.rulerView?.gutterView?.textColor = theme.textColor.withAlphaComponent(0.5)
        context.coordinator.rulerView?.gutterView?.gitStatuses = gitStatuses
        context.coordinator.rulerView?.needsDisplay = true
        context.coordinator.updateSyntaxHighlighterTheme(theme)
    }

    final class Coordinator: NSObject {
        var parent: EditorView
        weak var textView: MarkdownTextView?
        weak var scrollView: NSScrollView?
        weak var rulerView: GutterRulerView?
        var syntaxHighlighter: SyntaxHighlighter?
        private var isUpdating = false

        init(_ parent: EditorView) {
            self.parent = parent
        }

        func textDidChange(_ newText: String, textView: MarkdownTextView) {
            guard !isUpdating else { return }
            isUpdating = true
            parent.document.text = newText
            syntaxHighlighter?.textDidChange()
            updateLineRects()
            isUpdating = false
        }

        @objc func textViewDidChangeLayout(_ notification: Notification) {
            updateLineRects()
        }

        func updateLineRects() {
            guard let textView = textView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer,
                  let scrollView = scrollView
            else { return }

            let visibleRect = scrollView.contentView.bounds
            let textContainerInset = textView.textContainerInset

            let text = textView.string as NSString
            var lineRects: [(lineNumber: Int, rect: NSRect)] = []
            var lineNumber = 1
            var glyphIndex = 0
            let numberOfGlyphs = layoutManager.numberOfGlyphs

            while glyphIndex < numberOfGlyphs {
                var lineGlyphRange = NSRange()
                let lineRect = layoutManager.lineFragmentRect(
                    forGlyphAt: glyphIndex,
                    effectiveRange: &lineGlyphRange
                )

                let adjustedRect = NSRect(
                    x: lineRect.origin.x,
                    y: lineRect.origin.y + textContainerInset.height,
                    width: lineRect.width,
                    height: lineRect.height
                )

                if adjustedRect.maxY >= visibleRect.minY && adjustedRect.minY <= visibleRect.maxY {
                    lineRects.append((lineNumber, adjustedRect))
                }

                let charRange = layoutManager.characterRange(
                    forGlyphRange: lineGlyphRange,
                    actualGlyphRange: nil
                )

                // Count newlines within this line fragment to handle wrapped lines
                var idx = charRange.location
                let end = NSMaxRange(charRange)
                while idx < end {
                    if idx == text.length - 1 || text.character(at: idx) == 0x0A {
                        lineNumber += 1
                    }
                    idx += 1
                }

                glyphIndex = NSMaxRange(lineGlyphRange)
            }

            // Handle empty document
            if lineRects.isEmpty {
                let rect = NSRect(x: 0, y: textContainerInset.height, width: 100, height: 18)
                lineRects.append((1, rect))
            }

            rulerView?.gutterView?.lineRects = lineRects
            rulerView?.needsDisplay = true
        }

        func setupSyntaxHighlighter(textView: MarkdownTextView, theme: EditorTheme) {
            syntaxHighlighter = SyntaxHighlighter(textView: textView, theme: theme)
            syntaxHighlighter?.invalidate()
        }

        func updateSyntaxHighlighterTheme(_ theme: EditorTheme) {
            syntaxHighlighter?.theme = theme
            syntaxHighlighter?.invalidate()
        }
    }
}

/// A ruler view that hosts the GutterView for line numbers and git indicators.
final class GutterRulerView: NSRulerView {
    var gutterView: GutterView?
    weak var textView: MarkdownTextView?

    override var requiredThickness: CGFloat {
        GutterView.gutterWidth
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let gutterView = gutterView else { return }
        gutterView.frame = bounds
        gutterView.draw(dirtyRect)
    }
}
