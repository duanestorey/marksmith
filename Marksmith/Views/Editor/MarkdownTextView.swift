import AppKit

final class MarkdownTextView: NSTextView {
    var onTextChange: ((String) -> Void)?

    private let gutterView = GutterView()
    private var lineNumberTimer: Timer?

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        drawsBackground = true
        allowsUndo = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isRichText = false
        usesFindBar = true
        isIncrementalSearchingEnabled = true
        importsGraphics = false

        font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        textContainerInset = NSSize(width: 4, height: 8)

        setupNotifications()
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleFormatBold),
            name: .editorFormatBold, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleFormatItalic),
            name: .editorFormatItalic, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleFormatCode),
            name: .editorFormatCode, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleFormatH1),
            name: .editorFormatH1, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleFormatH2),
            name: .editorFormatH2, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleFormatH3),
            name: .editorFormatH3, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleFormatLink),
            name: .editorFormatLink, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleFormatImage),
            name: .editorFormatImage, object: nil)
    }

    // MARK: - Formatting

    @objc private func handleFormatBold() { wrapSelection(prefix: "**", suffix: "**") }
    @objc private func handleFormatItalic() { wrapSelection(prefix: "_", suffix: "_") }
    @objc private func handleFormatCode() { wrapSelection(prefix: "`", suffix: "`") }

    @objc private func handleFormatH1() { prefixLine(with: "# ") }
    @objc private func handleFormatH2() { prefixLine(with: "## ") }
    @objc private func handleFormatH3() { prefixLine(with: "### ") }

    @objc private func handleFormatLink() {
        let selectedText = selectedText()
        if selectedText.isEmpty {
            insertText("[link text](url)", replacementRange: selectedRange())
        } else {
            wrapSelection(prefix: "[", suffix: "](url)")
        }
    }

    @objc private func handleFormatImage() {
        let selectedText = selectedText()
        if selectedText.isEmpty {
            insertText("![alt text](image-url)", replacementRange: selectedRange())
        } else {
            wrapSelection(prefix: "![", suffix: "](image-url)")
        }
    }

    private func selectedText() -> String {
        guard let storage = textStorage else { return "" }
        let range = selectedRange()
        guard range.length > 0 else { return "" }
        return (storage.string as NSString).substring(with: range)
    }

    private func wrapSelection(prefix: String, suffix: String) {
        let range = selectedRange()
        let selected = selectedText()
        let replacement = "\(prefix)\(selected)\(suffix)"

        if shouldChangeText(in: range, replacementString: replacement) {
            textStorage?.replaceCharacters(in: range, with: replacement)
            didChangeText()
            let newCursorPos = range.location + prefix.count + selected.count
            setSelectedRange(NSRange(location: newCursorPos, length: 0))
        }
    }

    private func prefixLine(with prefix: String) {
        guard let storage = textStorage else { return }
        let text = storage.string as NSString
        let lineRange = text.lineRange(for: selectedRange())
        let lineText = text.substring(with: lineRange)

        // Remove existing heading prefix if present
        let stripped = lineText.replacingOccurrences(
            of: "^#{1,6}\\s*", with: "", options: .regularExpression)
        let replacement = prefix + stripped

        if shouldChangeText(in: lineRange, replacementString: replacement) {
            textStorage?.replaceCharacters(in: lineRange, with: replacement)
            didChangeText()
        }
    }

    override func didChangeText() {
        super.didChangeText()
        onTextChange?(string)
    }

    // MARK: - Theme

    func applyTheme(_ theme: EditorTheme) {
        backgroundColor = theme.backgroundColor
        insertionPointColor = theme.cursorColor
        selectedTextAttributes = [
            .backgroundColor: theme.selectionColor
        ]
        textColor = theme.textColor
        font = .monospacedSystemFont(ofSize: theme.fontSize, weight: .regular)
    }
}

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
