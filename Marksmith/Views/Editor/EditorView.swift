import SwiftUI
import AppKit

struct EditorView: NSViewRepresentable {
    @ObservedObject var document: MarkdownDocument
    var theme: EditorTheme
    var gitStatuses: [Int: GitLineStatus]
    var spellCheckEnabled: Bool
    var grammarCheckEnabled: Bool
    var spellingLanguage: String
    var scrollToLine: Int = 0
    var onScrollLineChange: ((Int) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        // Configure text view
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = spellCheckEnabled
        textView.isGrammarCheckingEnabled = grammarCheckEnabled
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.importsGraphics = false
        textView.drawsBackground = true
        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textContainerInset = NSSize(width: 4, height: 8)
        textView.textContainer?.lineFragmentPadding = 4

        textView.delegate = context.coordinator

        if !spellingLanguage.isEmpty {
            NSSpellChecker.shared.automaticallyIdentifiesLanguages = false
            NSSpellChecker.shared.setLanguage(spellingLanguage)
        } else {
            NSSpellChecker.shared.automaticallyIdentifiesLanguages = true
        }

        // Set up gutter
        let gutterView = GutterView()
        gutterView.font = textView.font ?? .monospacedSystemFont(ofSize: 14, weight: .regular)

        let rulerView = GutterRulerView(scrollView: scrollView, orientation: .verticalRuler)
        rulerView.clipsToBounds = true
        rulerView.gutterView = gutterView
        rulerView.ruleThickness = GutterView.gutterWidth
        scrollView.verticalRulerView = rulerView
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        context.coordinator.rulerView = rulerView
        context.coordinator.setupSyntaxHighlighter(textView: textView, theme: theme)
        context.coordinator.setupFormattingNotifications()

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

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = context.coordinator.textView else { return }

        // Sync text from document to editor
        let textChanged = textView.string != document.text
        if textChanged {
            let selectedRanges = textView.selectedRanges
            textView.string = document.text
            textView.selectedRanges = selectedRanges
        }

        // Apply theme properties that don't touch text storage
        textView.backgroundColor = theme.backgroundColor
        textView.insertionPointColor = theme.cursorColor
        textView.selectedTextAttributes = [
            .backgroundColor: theme.selectionColor
        ]

        // Sync spell checking settings
        if textView.isContinuousSpellCheckingEnabled != spellCheckEnabled {
            textView.isContinuousSpellCheckingEnabled = spellCheckEnabled
        }
        if textView.isGrammarCheckingEnabled != grammarCheckEnabled {
            textView.isGrammarCheckingEnabled = grammarCheckEnabled
        }

        // Sync spelling language
        let currentLang = NSSpellChecker.shared.language()
        if spellingLanguage.isEmpty {
            NSSpellChecker.shared.automaticallyIdentifiesLanguages = true
        } else if currentLang != spellingLanguage {
            NSSpellChecker.shared.automaticallyIdentifiesLanguages = false
            NSSpellChecker.shared.setLanguage(spellingLanguage)
        }

        // Update syntax highlighter theme and re-highlight if needed
        // NOTE: Don't set textView.textColor or textView.font here — those modify
        // text storage attributes and wipe out syntax highlighting colors.
        // The SyntaxHighlighter.invalidate() sets base font + color via setAttributes.
        let highlighter = context.coordinator.syntaxHighlighter
        if highlighter?.theme.fontSize != theme.fontSize || textChanged {
            highlighter?.theme = theme
            highlighter?.invalidate()
        }

        // Update gutter
        context.coordinator.rulerView?.gutterView?.backgroundColor = theme.backgroundColor.blended(
            withFraction: 0.05, of: .gray) ?? theme.backgroundColor
        context.coordinator.rulerView?.gutterView?.textColor = theme.textColor.withAlphaComponent(0.5)
        context.coordinator.rulerView?.gutterView?.gitStatuses = gitStatuses
        context.coordinator.rulerView?.needsDisplay = true

        // Scroll sync: scroll to target line if changed
        if scrollToLine > 0, scrollToLine != context.coordinator.lastScrolledToLine {
            context.coordinator.lastScrolledToLine = scrollToLine
            context.coordinator.performScrollToLine(scrollToLine)
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EditorView
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        weak var rulerView: GutterRulerView?
        var syntaxHighlighter: SyntaxHighlighter?
        var lastThemeFontSize: CGFloat = 0
        var lastThemeIsDark: Bool?
        var lastScrolledToLine: Int = 0
        private var isUpdating = false
        private var isProgrammaticScroll = false
        private var scrollReportTimer: Timer?

        init(_ parent: EditorView) {
            self.parent = parent
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        // MARK: - NSTextViewDelegate

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let textView = textView else { return }
            isUpdating = true
            parent.document.text = textView.string
            syntaxHighlighter?.textDidChange()
            updateLineRects()
            isUpdating = false
        }

        func textView(_ textView: NSTextView, shouldSetSpellingState value: Int, range: NSRange) -> Int {
            guard let storage = textView.textStorage, range.location < storage.length else {
                return value
            }

            let text = storage.string

            // Skip front matter (YAML between --- delimiters at document start)
            if isInFrontMatter(range: range, text: text) {
                return 0
            }

            // Check foreground color at this range against theme colors to skip
            let checkLocation = min(range.location, storage.length - 1)
            let attrs = storage.attributes(at: checkLocation, effectiveRange: nil)
            if let color = attrs[.foregroundColor] as? NSColor {
                let theme = parent.theme
                // Skip code (fenced blocks + inline) and link URLs
                if color.isClose(to: theme.codeColor) || color.isClose(to: theme.linkURLColor) {
                    return 0
                }
            }

            // Skip text that looks like a URL (catches image URLs colored as linkColor)
            let nsText = text as NSString
            if range.location + range.length <= nsText.length {
                let word = nsText.substring(with: range)
                if word.contains("://") || word.hasPrefix("www.") {
                    return 0
                }
            }

            return value
        }

        private func isInFrontMatter(range: NSRange, text: String) -> Bool {
            let nsText = text as NSString
            // Front matter must start at the very beginning of the document
            guard nsText.length >= 3, nsText.substring(with: NSRange(location: 0, length: 3)) == "---" else {
                return false
            }
            // Find the closing ---
            let searchStart = nsText.lineRange(for: NSRange(location: 0, length: 0)).length
            let searchRange = NSRange(location: searchStart, length: nsText.length - searchStart)
            let closingRange = nsText.range(of: "^---", options: .regularExpression, range: searchRange)
            guard closingRange.location != NSNotFound else {
                return false
            }
            let frontMatterEnd = NSMaxRange(closingRange)
            // Check if the spelling range falls within front matter
            return range.location < frontMatterEnd
        }

        // MARK: - Layout notifications

        @objc func textViewDidChangeLayout(_ notification: Notification) {
            guard !isUpdating else { return }
            isUpdating = true
            updateLineRects()
            scheduleVisibleLineReport()
            isUpdating = false
        }

        // MARK: - Scroll sync

        private func scheduleVisibleLineReport() {
            guard !isProgrammaticScroll else { return }
            scrollReportTimer?.invalidate()
            scrollReportTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
                self?.reportFirstVisibleLine()
            }
        }

        private func reportFirstVisibleLine() {
            guard let textView = textView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer,
                  let scrollView = scrollView else { return }

            let text = textView.string as NSString
            guard text.length > 0 else { return }

            let visibleRect = scrollView.contentView.bounds
            let textContainerInset = textView.textContainerInset
            let containerRect = NSRect(
                x: 0,
                y: visibleRect.origin.y - textContainerInset.height,
                width: textContainer.size.width,
                height: visibleRect.height
            )
            let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: containerRect, in: textContainer)
            guard visibleGlyphRange.length > 0 else { return }

            let firstVisibleChar = layoutManager.characterRange(
                forGlyphRange: NSRange(location: visibleGlyphRange.location, length: 1),
                actualGlyphRange: nil
            ).location

            var lineNumber = 1
            for i in 0..<min(firstVisibleChar, text.length) {
                if text.character(at: i) == 0x0A {
                    lineNumber += 1
                }
            }

            parent.onScrollLineChange?(lineNumber)
        }

        func performScrollToLine(_ line: Int) {
            guard let textView = textView,
                  let layoutManager = textView.layoutManager,
                  let scrollView = scrollView else { return }

            let text = textView.string as NSString
            guard text.length > 0 else { return }

            // Find character index for the start of the target line
            var currentLine = 1
            var charIndex = 0
            while currentLine < line && charIndex < text.length {
                if text.character(at: charIndex) == 0x0A {
                    currentLine += 1
                }
                charIndex += 1
            }
            guard charIndex < text.length else { return }

            // Get line fragment rect for this character
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: charIndex)
            var lineRange = NSRange()
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &lineRange)

            // Scroll so this line is at the top
            isProgrammaticScroll = true
            let scrollY = lineRect.origin.y + textView.textContainerInset.height
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: scrollY))
            scrollView.reflectScrolledClipView(scrollView.contentView)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.isProgrammaticScroll = false
            }
        }

        // MARK: - Formatting commands

        func setupFormattingNotifications() {
            let nc = NotificationCenter.default
            nc.addObserver(self, selector: #selector(handleFormatBold), name: .editorFormatBold, object: nil)
            nc.addObserver(self, selector: #selector(handleFormatItalic), name: .editorFormatItalic, object: nil)
            nc.addObserver(self, selector: #selector(handleFormatCode), name: .editorFormatCode, object: nil)
            nc.addObserver(self, selector: #selector(handleFormatH1), name: .editorFormatH1, object: nil)
            nc.addObserver(self, selector: #selector(handleFormatH2), name: .editorFormatH2, object: nil)
            nc.addObserver(self, selector: #selector(handleFormatH3), name: .editorFormatH3, object: nil)
            nc.addObserver(self, selector: #selector(handleFormatLink), name: .editorFormatLink, object: nil)
            nc.addObserver(self, selector: #selector(handleFormatImage), name: .editorFormatImage, object: nil)
        }

        private var isFirstResponder: Bool {
            guard let textView = textView else { return false }
            return textView.window?.firstResponder == textView
        }

        @objc private func handleFormatBold() { guard isFirstResponder else { return }; wrapSelection(prefix: "**", suffix: "**") }
        @objc private func handleFormatItalic() { guard isFirstResponder else { return }; wrapSelection(prefix: "_", suffix: "_") }
        @objc private func handleFormatCode() { guard isFirstResponder else { return }; wrapSelection(prefix: "`", suffix: "`") }
        @objc private func handleFormatH1() { guard isFirstResponder else { return }; prefixLine(with: "# ") }
        @objc private func handleFormatH2() { guard isFirstResponder else { return }; prefixLine(with: "## ") }
        @objc private func handleFormatH3() { guard isFirstResponder else { return }; prefixLine(with: "### ") }

        @objc private func handleFormatLink() {
            guard isFirstResponder, let textView = textView else { return }
            let selected = selectedText()
            if selected.isEmpty {
                textView.insertText("[link text](url)", replacementRange: textView.selectedRange())
            } else {
                wrapSelection(prefix: "[", suffix: "](url)")
            }
        }

        @objc private func handleFormatImage() {
            guard isFirstResponder, let textView = textView else { return }
            let selected = selectedText()
            if selected.isEmpty {
                textView.insertText("![alt text](image-url)", replacementRange: textView.selectedRange())
            } else {
                wrapSelection(prefix: "![", suffix: "](image-url)")
            }
        }

        private func selectedText() -> String {
            guard let textView = textView, let storage = textView.textStorage else { return "" }
            let range = textView.selectedRange()
            guard range.length > 0 else { return "" }
            return (storage.string as NSString).substring(with: range)
        }

        private func wrapSelection(prefix: String, suffix: String) {
            guard let textView = textView else { return }
            let range = textView.selectedRange()
            let selected = selectedText()
            let replacement = "\(prefix)\(selected)\(suffix)"

            if textView.shouldChangeText(in: range, replacementString: replacement) {
                textView.textStorage?.replaceCharacters(in: range, with: replacement)
                textView.didChangeText()
                let newCursorPos = range.location + prefix.utf16.count + selected.utf16.count
                textView.setSelectedRange(NSRange(location: newCursorPos, length: 0))
            }
        }

        private func prefixLine(with prefix: String) {
            guard let textView = textView, let storage = textView.textStorage else { return }
            let text = storage.string as NSString
            let lineRange = text.lineRange(for: textView.selectedRange())
            let lineText = text.substring(with: lineRange)

            let stripped = lineText.replacingOccurrences(
                of: "^#{1,6}\\s*", with: "", options: .regularExpression)
            let replacement = prefix + stripped

            if textView.shouldChangeText(in: lineRange, replacementString: replacement) {
                storage.replaceCharacters(in: lineRange, with: replacement)
                textView.didChangeText()
            }
        }

        // MARK: - Line rects for gutter

        func updateLineRects() {
            rulerView?.needsDisplay = true
        }

        func setupSyntaxHighlighter(textView: NSTextView, theme: EditorTheme) {
            syntaxHighlighter = SyntaxHighlighter(textView: textView, theme: theme)
        }
    }
}

/// A ruler view that computes and draws line numbers directly on each draw call.
final class GutterRulerView: NSRulerView {
    var gutterView: GutterView?

    override var requiredThickness: CGFloat {
        GutterView.gutterWidth
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let gutter = gutterView,
              let scrollView = self.scrollView,
              let textView = scrollView.documentView as? NSTextView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer
        else { return }

        // Fill background
        gutter.backgroundColor.setFill()
        rect.fill()

        let text = textView.string as NSString
        guard text.length > 0 else { return }

        let textContainerInset = textView.textContainerInset
        let visibleRect = scrollView.contentView.bounds

        // Get glyph range for the visible area
        let containerRect = NSRect(
            x: 0,
            y: visibleRect.origin.y - textContainerInset.height,
            width: textContainer.size.width,
            height: visibleRect.height
        )
        let visibleGlyphRange = layoutManager.glyphRange(
            forBoundingRect: containerRect,
            in: textContainer
        )
        guard visibleGlyphRange.length > 0 else { return }

        // Count newlines before visible range to get starting line number
        let firstVisibleChar = layoutManager.characterRange(
            forGlyphRange: NSRange(location: visibleGlyphRange.location, length: 1),
            actualGlyphRange: nil
        ).location
        var lineNumber = 1
        for i in 0..<min(firstVisibleChar, text.length) {
            if text.character(at: i) == 0x0A {
                lineNumber += 1
            }
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: gutter.font.pointSize - 2, weight: .regular),
            .foregroundColor: gutter.textColor
        ]

        var glyphIndex = visibleGlyphRange.location
        let endGlyph = NSMaxRange(visibleGlyphRange)
        var lastDrawnLineNumber = -1

        while glyphIndex < endGlyph {
            var lineGlyphRange = NSRange()
            let lineRect = layoutManager.lineFragmentRect(
                forGlyphAt: glyphIndex,
                effectiveRange: &lineGlyphRange
            )

            // Map text view coordinate to ruler view coordinate
            let textViewPoint = NSPoint(x: 0, y: lineRect.origin.y + textContainerInset.height)
            let rulerPoint = convert(textViewPoint, from: textView)

            // Only draw line number on the first visual line of each logical line
            if lineNumber != lastDrawnLineNumber {
                let numStr = "\(lineNumber)" as NSString
                let size = numStr.size(withAttributes: attrs)
                let x = GutterView.gutterWidth - size.width - 12
                let drawY = rulerPoint.y + (lineRect.height - size.height) / 2
                numStr.draw(at: NSPoint(x: x, y: drawY), withAttributes: attrs)

                // Draw git indicator
                let indicatorRect = NSRect(x: 0, y: rulerPoint.y, width: GutterView.gutterWidth, height: lineRect.height)
                drawGitIndicator(status: gutter.gitStatuses[lineNumber] ?? .unchanged, in: indicatorRect)

                lastDrawnLineNumber = lineNumber
            }

            // Advance line number if this fragment ends with a newline
            let charRange = layoutManager.characterRange(
                forGlyphRange: lineGlyphRange,
                actualGlyphRange: nil
            )
            let lastChar = NSMaxRange(charRange) - 1
            if lastChar >= 0 && lastChar < text.length && text.character(at: lastChar) == 0x0A {
                lineNumber += 1
            }

            glyphIndex = NSMaxRange(lineGlyphRange)
        }
    }

    private func drawGitIndicator(status: GitLineStatus, in rect: NSRect) {
        guard status != .unchanged else { return }
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

// MARK: - Editor Theme

struct EditorTheme {
    let backgroundColor: NSColor
    let textColor: NSColor
    let cursorColor: NSColor
    let selectionColor: NSColor
    let fontSize: CGFloat

    let headingColor: NSColor
    let boldColor: NSColor
    let italicColor: NSColor
    let codeColor: NSColor
    let linkColor: NSColor
    let linkURLColor: NSColor
    let blockQuoteColor: NSColor
    let listMarkerColor: NSColor

    static let light = EditorTheme(
        backgroundColor: NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),
        textColor: NSColor(red: 0.15, green: 0.16, blue: 0.18, alpha: 1.0),
        cursorColor: NSColor(red: 0.20, green: 0.25, blue: 0.80, alpha: 1.0),
        selectionColor: NSColor(red: 0.80, green: 0.85, blue: 0.95, alpha: 1.0),
        fontSize: 14,
        headingColor: NSColor(red: 0.10, green: 0.10, blue: 0.60, alpha: 1.0),
        boldColor: NSColor(red: 0.15, green: 0.16, blue: 0.18, alpha: 1.0),
        italicColor: NSColor(red: 0.40, green: 0.20, blue: 0.50, alpha: 1.0),
        codeColor: NSColor(red: 0.75, green: 0.15, blue: 0.15, alpha: 1.0),
        linkColor: NSColor(red: 0.10, green: 0.40, blue: 0.70, alpha: 1.0),
        linkURLColor: NSColor(red: 0.50, green: 0.50, blue: 0.55, alpha: 1.0),
        blockQuoteColor: NSColor(red: 0.40, green: 0.45, blue: 0.50, alpha: 1.0),
        listMarkerColor: NSColor(red: 0.30, green: 0.50, blue: 0.30, alpha: 1.0)
    )

    static let dark = EditorTheme(
        backgroundColor: NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1.0),
        textColor: NSColor(red: 0.85, green: 0.85, blue: 0.87, alpha: 1.0),
        cursorColor: NSColor(red: 0.55, green: 0.65, blue: 1.0, alpha: 1.0),
        selectionColor: NSColor(red: 0.20, green: 0.25, blue: 0.40, alpha: 1.0),
        fontSize: 14,
        headingColor: NSColor(red: 0.55, green: 0.65, blue: 1.0, alpha: 1.0),
        boldColor: NSColor(red: 0.90, green: 0.90, blue: 0.92, alpha: 1.0),
        italicColor: NSColor(red: 0.75, green: 0.55, blue: 0.85, alpha: 1.0),
        codeColor: NSColor(red: 0.95, green: 0.55, blue: 0.45, alpha: 1.0),
        linkColor: NSColor(red: 0.45, green: 0.70, blue: 1.0, alpha: 1.0),
        linkURLColor: NSColor(red: 0.50, green: 0.55, blue: 0.60, alpha: 1.0),
        blockQuoteColor: NSColor(red: 0.55, green: 0.60, blue: 0.65, alpha: 1.0),
        listMarkerColor: NSColor(red: 0.45, green: 0.70, blue: 0.45, alpha: 1.0)
    )
}

// MARK: - NSColor Comparison

extension NSColor {
    func isClose(to other: NSColor, tolerance: CGFloat = 0.01) -> Bool {
        guard let c1 = self.usingColorSpace(.deviceRGB),
              let c2 = other.usingColorSpace(.deviceRGB) else {
            return false
        }
        return abs(c1.redComponent - c2.redComponent) < tolerance
            && abs(c1.greenComponent - c2.greenComponent) < tolerance
            && abs(c1.blueComponent - c2.blueComponent) < tolerance
            && abs(c1.alphaComponent - c2.alphaComponent) < tolerance
    }
}
