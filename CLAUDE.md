# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
make setup      # One-time: brew install xcodegen
make generate   # Generate Marksmith.xcodeproj from project.yml
make build      # Release build (generates project first)
make debug      # Debug build
make run        # Debug build + launch app
make open       # Generate project + open in Xcode
make clean      # Remove build/ and .xcodeproj
```

Build output lands in `build/Build/Products/{Debug|Release}/Marksmith.app`.

To install for testing: `cp -R build/Build/Products/Debug/Marksmith.app /Applications/Marksmith.app`

## Architecture

SwiftUI document-based macOS app (macOS 14+, Swift 5.10) using XcodeGen for project generation. The only external dependency is `swift-markdown` for Markdown→HTML conversion.

### Hybrid SwiftUI + AppKit

The app shell (window management, toolbar, preferences, split pane) is SwiftUI. The editor and preview are AppKit views bridged via `NSViewRepresentable`:

- **Editor**: Plain `NSTextView` (no subclass) → wrapped by `EditorView` via Coordinator
- **Preview**: `WKWebView` → wrapped by `PreviewView`
- **Gutter**: `GutterView` (data container) + `GutterRulerView` (NSRulerView) attached to the editor's scroll view

### Document Model

`MarkdownDocument` implements `ReferenceFileDocument`. It holds a `@Published var text: String` and registers for UTType `net.daringfireball.markdown`. The SwiftUI `DocumentGroup` in `MarksmithApp` passes both `file.document` and `file.fileURL` to `ContentView`.

### Data Flow

1. User types → `NSTextViewDelegate.textDidChange()` → Coordinator sets `document.text`
2. `document.text` change triggers `ContentView.updatePreview()` → background queue runs `MarkdownHTMLGenerator.generateFullPage()` → result loaded into WKWebView on main thread
3. `document.text` change also triggers `gitStatus.diffBuffer()` → 300ms debounced in-memory diff against HEAD content
4. Syntax highlighting runs via `SyntaxHighlighter.textDidChange()` with 50ms debounce

### Command Dispatch

Formatting commands (bold, italic, headings, etc.) use `NotificationCenter` posts from the menu/toolbar, observed by the EditorView Coordinator. This decouples UI triggers from editor logic. All notification names are defined as extensions on `Notification.Name` in `MarksmithApp.swift`.

### Theme System

Editor and preview themes are independent. Each has a three-way setting (System/Light/Dark) stored via `@AppStorage`. `EditorTheme` is a struct with color properties applied to the NSTextView. Preview theme is a CSS class (`light`/`dark`/`auto`) on the `<html>` element, with separate stylesheets for each mode.

### Git Integration

`GitStatusProvider` (ObservableObject, `@StateObject` in ContentView) detects the repo root and fetches HEAD content via `git show HEAD:<path>`. It uses Swift's `CollectionDifference` (Myers algorithm) to diff the live buffer against HEAD, debounced at 300ms. Line-level statuses (`added`/`modified`/`deleted`) feed into `GutterRulerView` for colored indicators. It re-fetches HEAD on window focus (`NSApplication.didBecomeActiveNotification`).

**Thread safety pattern:** `backgroundRepoRoot` (private var set on background queue) mirrors `repoRoot` (@Published, set on main thread). Background queue code uses `backgroundRepoRoot`; UI reads `repoRoot`.

`GitService` handles commit/push and `git status --porcelain -uall` for the commit sheet file list. `GitFileStatus` model provides display labels and colors.

`CommitSheetView` shows a scrollable file list with colored status labels (Modified/Added/Deleted/Untracked), commit message editor, stage-all and push toggles.

### SSG Integration

`SSGService` (ObservableObject, `@StateObject` in ContentView) runs build/serve commands as background `Process` instances. It auto-detects localhost URLs from stdout via regex and strips ANSI escape sequences from output. Preferences (`@AppStorage`) store build command, serve command, and optional URL override.

**Build:** One-shot process, output shown in build output panel.
**Serve:** Long-running process with streaming output, play/stop toggle in toolbar, globe button with URL link to open in browser.

**Build output panel** appears as a sub-split inside the editor pane, opposite direction to main split (HSplitView when main is VSplitView, and vice versa). Terminal-style dark background with green monospace text. URLs in output are clickable (cyan, underlined, open in browser). Close button kills process.

**SSGService.deinit:** Terminates process directly — must NOT call `stop()` which dispatches to main thread (causes crash during deallocation).

### Front Matter

`MarkdownHTMLGenerator` strips YAML front matter (`---` delimited) before parsing markdown. Front matter is rendered as a collapsible `<details>` table with styled key-value pairs. CSS for front matter is in both `preview-light.css` and `preview-dark.css`.

## Key Patterns

- **Regex-based syntax highlighting** in `SyntaxHighlighter` — pattern order matters (fenced code blocks must match before inline patterns to avoid conflicts)
- **All `NSView` subclasses are layer-backed** (`wantsLayer = true`) for GPU compositing
- **Gutter line positioning** uses the layout manager's `lineFragmentRect` to align line numbers with text, recalculated on scroll/layout changes
- **`MarkdownHTMLGenerator`** uses swift-markdown's `MarkupWalker` protocol; the `HTMLRenderer` struct walks the AST and emits HTML with `data-line` attributes for scroll sync
- **Preview resources** (CSS, Prism.js, HTML template) are bundled in `Resources/` and referenced via `Bundle.main.resourceURL`
- **App icon** is in `Resources/Assets.xcassets/AppIcon.appiconset/` — generated via Swift script, cursive "M" on white background

## Project Configuration

- `project.yml` — XcodeGen spec (target, dependencies, build settings, entitlements)
- `Info.plist` — document type registration for .md/.markdown/.mdown/.mkd, copyright info
- `Marksmith.entitlements` — sandbox with file access, network client, subprocess execution
- `Assets.xcassets` — app icon asset catalog (referenced via `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` in project.yml)
