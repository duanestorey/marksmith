# Spelling & Grammar Checking Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add markdown-aware spelling and grammar checking with language selection for US, British, and Canadian English.

**Architecture:** Use macOS's built-in `NSSpellChecker` via `NSTextView` properties. Filter non-prose markdown elements by checking foreground color attributes already set by `SyntaxHighlighter`. Preferences stored via `@AppStorage`, synced to the text view in `updateNSView()`.

**Tech Stack:** Swift/AppKit (`NSSpellChecker`, `NSTextView`), SwiftUI (`@AppStorage`, preferences UI)

---

### Task 1: Add SpellingLanguage enum and preferences UI

**Files:**
- Modify: `Marksmith/Views/Preferences/PreferencesView.swift`

**Step 1: Add SpellingLanguage enum**

Add this enum at the bottom of `PreferencesView.swift` (after `SSGPreferencesView`):

```swift
enum SpellingLanguage: String, CaseIterable {
    case automatic = ""
    case enUS = "en_US"
    case enGB = "en_GB"
    case enCA = "en_CA"

    var label: String {
        switch self {
        case .automatic: return "Automatic"
        case .enUS: return "US English"
        case .enGB: return "British English"
        case .enCA: return "Canadian English"
        }
    }
}
```

**Step 2: Add spelling/grammar preferences to GeneralPreferencesView**

Add three new `@AppStorage` properties to `GeneralPreferencesView`:

```swift
@AppStorage("spellCheckEnabled") private var spellCheckEnabled = true
@AppStorage("grammarCheckEnabled") private var grammarCheckEnabled = false
@AppStorage("spellingLanguage") private var spellingLanguage: SpellingLanguage = .automatic
```

Add a new "Spelling & Grammar" section in the `Form`, after the existing "Editor" section:

```swift
Section("Spelling & Grammar") {
    Toggle("Check spelling while typing", isOn: $spellCheckEnabled)

    Toggle("Check grammar", isOn: $grammarCheckEnabled)

    Picker("Language", selection: $spellingLanguage) {
        ForEach(SpellingLanguage.allCases, id: \.self) { lang in
            Text(lang.label).tag(lang)
        }
    }
}
```

**Step 3: Build and verify**

Run: `make build`
Expected: Clean build, no errors.

**Step 4: Commit**

```
feat: add spelling/grammar preferences UI with language selection
```

---

### Task 2: Wire spell/grammar settings into EditorView

**Files:**
- Modify: `Marksmith/Views/Editor/EditorView.swift`
- Modify: `Marksmith/Views/ContentView.swift`

**Step 1: Add spell/grammar properties to EditorView**

Add three new properties to the `EditorView` struct (after `gitStatuses`):

```swift
var spellCheckEnabled: Bool
var grammarCheckEnabled: Bool
var spellingLanguage: String
```

**Step 2: Configure NSTextView in makeNSView**

In `makeNSView`, after line 26 (`isAutomaticSpellingCorrectionEnabled = false`), add:

```swift
textView.isContinuousSpellCheckingEnabled = spellCheckEnabled
textView.isGrammarCheckingEnabled = grammarCheckEnabled
```

Also, after the delegate assignment (line 35), add language configuration:

```swift
if !spellingLanguage.isEmpty {
    NSSpellChecker.shared.setLanguage(spellingLanguage)
}
```

**Step 3: Sync settings in updateNSView**

In `updateNSView`, after the theme application block (after the `selectedTextAttributes` assignment around line 89), add:

```swift
// Sync spell checking settings
if textView.isContinuousSpellCheckingEnabled != spellCheckEnabled {
    textView.isContinuousSpellCheckingEnabled = spellCheckEnabled
}
if textView.isGrammarCheckingEnabled != grammarCheckEnabled {
    textView.isGrammarCheckingEnabled = grammarCheckEnabled
}
```

**Step 4: Pass settings from ContentView**

In `ContentView.swift`, add `@AppStorage` properties (with the other AppStorage declarations near the top):

```swift
@AppStorage("spellCheckEnabled") private var spellCheckEnabled = true
@AppStorage("grammarCheckEnabled") private var grammarCheckEnabled = false
@AppStorage("spellingLanguage") private var spellingLanguage: SpellingLanguage = .automatic
```

Update `editorContent` to pass the new properties:

```swift
private var editorContent: some View {
    EditorView(
        document: document,
        theme: editorTheme,
        gitStatuses: gitStatus.lineStatuses,
        spellCheckEnabled: spellCheckEnabled,
        grammarCheckEnabled: grammarCheckEnabled,
        spellingLanguage: spellingLanguage.rawValue
    )
    .frame(minWidth: 200, minHeight: 100)
}
```

**Step 5: Build and verify**

Run: `make build`
Expected: Clean build, no errors.

**Step 6: Manual test**

Run: `make run`
- Open a markdown file or type some text with a misspelling (e.g., "teh" instead of "the")
- Verify red squiggly underline appears under misspelled words
- Open Preferences > General > Spelling & Grammar
- Toggle "Check spelling while typing" off — underlines should disappear
- Toggle back on — underlines reappear
- Note: at this point, spell check will flag words inside code blocks too (Task 3 fixes this)

**Step 7: Commit**

```
feat: wire spell/grammar checking into editor with preference sync
```

---

### Task 3: Implement markdown-aware spell check filtering

**Files:**
- Modify: `Marksmith/Views/Editor/EditorView.swift`

**Step 1: Add shouldSetSpellingState delegate method**

Add this method to the `Coordinator` class, in the `NSTextViewDelegate` section (after `textDidChange`):

```swift
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
```

**Step 2: Add isInFrontMatter helper**

Add this private method to `Coordinator`:

```swift
private func isInFrontMatter(range: NSRange, text: String) -> Bool {
    let nsText = text as NSString
    // Front matter must start at the very beginning of the document
    guard nsText.length >= 3, nsText.substring(with: NSRange(location: 0, length: 3)) == "---" else {
        return false
    }
    // Find the closing ---
    let searchStart = nsText.lineRange(for: NSRange(location: 0, length: 0)).length
    let searchRange = NSRange(location: searchStart, length: nsText.length - searchStart)
    let closingRange = nsText.range(of: "---", options: [], range: searchRange)
    guard closingRange.location != NSNotFound else {
        return false
    }
    let frontMatterEnd = NSMaxRange(closingRange)
    // Check if the spelling range falls within front matter
    return range.location < frontMatterEnd
}
```

**Step 3: Add NSColor.isClose helper**

Add this extension at the bottom of `EditorView.swift` (after the `EditorTheme` struct). NSColor comparison needs tolerance because colors may be in different color spaces:

```swift
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
```

**Step 4: Build and verify**

Run: `make build`
Expected: Clean build, no errors.

**Step 5: Manual test**

Run: `make run`

Create or open a file with this content:
```markdown
---
title: Test Dokument
author: Test
---

# This is a headng with a typo

Some norml text with misspeled words.

`codeWithTypo` should not be flagged.

    ```python
    def functon_name():
        misspeled = True
    ```

[link txt](https://exmple.com/some-pth)

> A blockquote with a tpyo should be flagged.
```

Verify:
- "Dokument" in front matter is NOT flagged (front matter excluded)
- "headng" in the heading IS flagged (headings are checked)
- "norml" and "misspeled" in prose ARE flagged
- "codeWithTypo" in inline code is NOT flagged
- "functon_name" and "misspeled" inside the fenced code block are NOT flagged
- "exmple" and "pth" in the link URL are NOT flagged
- "txt" in the link display text IS flagged (link text is checked)
- "tpyo" in the blockquote IS flagged

**Step 6: Commit**

```
feat: add markdown-aware spell check filtering for code, URLs, and front matter
```

---

### Task 4: Handle language switching in updateNSView

**Files:**
- Modify: `Marksmith/Views/Editor/EditorView.swift`

**Step 1: Add language sync to updateNSView**

In `updateNSView`, after the spell checking sync block added in Task 2, add:

```swift
// Sync spelling language
let currentLang = NSSpellChecker.shared.language()
if spellingLanguage.isEmpty {
    NSSpellChecker.shared.automaticallyIdentifiesLanguages = true
} else if currentLang != spellingLanguage {
    NSSpellChecker.shared.automaticallyIdentifiesLanguages = false
    NSSpellChecker.shared.setLanguage(spellingLanguage)
}
```

**Step 2: Build and verify**

Run: `make build`
Expected: Clean build, no errors.

**Step 3: Manual test**

Run: `make run`
- Open Preferences > General > Spelling & Grammar
- Type "colour" — should NOT be flagged when language is British/Canadian English
- Switch to US English — "colour" should be flagged
- Switch to Automatic — defers to system
- Switch back to British English — "colour" should not be flagged

**Step 4: Commit**

```
feat: add language switching support for spell checker
```

---

### Task 5: Final verification and install

**Step 1: Full build**

Run: `make build`
Expected: Clean release build, no warnings related to new code.

**Step 2: Install and test**

```bash
cp -R build/Build/Products/Debug/Marksmith.app /Applications/Marksmith.app
```

Open `/Applications/Marksmith.app` and verify:
1. Spell checking works on plain prose
2. Code blocks, inline code, URLs, front matter are not flagged
3. Preferences toggles work (spell check on/off, grammar on/off)
4. Language switching works (US vs British "colour" test)
5. Edit > Spelling and Grammar menu works (Show Spelling and Grammar, Check Document Now)

**Step 3: Commit**

```
chore: final verification of spelling/grammar feature
```
