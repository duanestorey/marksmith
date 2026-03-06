# Spelling & Grammar Checking Design

## Goal

Add markdown-aware spelling and grammar checking with language selection (US, British, Canadian English).

## Approach: Attribute-Based Filtering

Use macOS's built-in `NSSpellChecker` via `NSTextView` properties. Filter non-prose markdown elements by checking foreground color attributes set by `SyntaxHighlighter`.

## Components

### 1. Core Enable/Disable

- `isContinuousSpellCheckingEnabled` and `isGrammarCheckingEnabled` on `NSTextView`
- Driven by `@AppStorage` preferences, synced in `updateNSView()`

### 2. Markdown-Aware Filtering

`NSTextViewDelegate.textView(_:shouldSetSpellingState:range:)` checks foreground color at range:
- **Skip (return 0):** code color, link URL color (covers fenced code blocks, inline code, URLs, image paths, link destinations)
- **Skip:** front matter region (between opening/closing `---`)
- **Allow (return value):** everything else (headings, bold, italic, blockquote text, list text, plain prose)

### 3. Preferences

In General > Editor section:
- Toggle: "Check spelling while typing" (default: true)
- Toggle: "Check grammar" (default: false)
- Picker: "Spelling language" — Automatic, US English, British English, Canadian English

### 4. Language

`NSSpellChecker.shared.setLanguage()` called based on preference. "Automatic" defers to system.

### 5. Menu

Standard Edit > Spelling and Grammar works via NSTextView responder chain. No custom code needed.

## Files Changed

- `EditorView.swift` — spell/grammar properties, delegate method, preference sync
- `PreferencesView.swift` — toggles and language picker
- `ContentView.swift` — pass `@AppStorage` values to `EditorView`

## Excluded from Spell Check

Fenced code blocks, inline code, link URLs, image URLs, front matter (YAML between `---` delimiters), HTML tags.

## Included in Spell Check

Headings, bold/italic text, blockquote prose, list item text, plain paragraphs, link display text.
