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

## Architecture

SwiftUI document-based macOS app (macOS 14+, Swift 5.10) using XcodeGen for project generation. The only external dependency is `swift-markdown` for Markdown→HTML conversion.

### Hybrid SwiftUI + AppKit

The app shell (window management, toolbar, preferences, split pane) is SwiftUI. The editor and preview are AppKit views bridged via `NSViewRepresentable`:

- **Editor**: `MarkdownTextView` (NSTextView subclass) → wrapped by `EditorView`
- **Preview**: `WKWebView` → wrapped by `PreviewView`
- **Gutter**: `GutterView` drawn inside a `GutterRulerView` (NSRulerView) attached to the editor's scroll view

### Document Model

`MarkdownDocument` implements `ReferenceFileDocument`. It holds a `@Published var text: String` and registers for UTType `net.daringfireball.markdown`. The SwiftUI `DocumentGroup` in `MarksmithApp` handles file open/save/create.

### Data Flow

1. User types → `MarkdownTextView.didChangeText()` → `onTextChange` callback → Coordinator sets `document.text`
2. `document.text` change triggers `ContentView.updatePreview()` → background queue runs `MarkdownHTMLGenerator.generateFullPage()` → result loaded into WKWebView on main thread
3. Syntax highlighting runs via `SyntaxHighlighter.textDidChange()` with 50ms debounce; preview updates debounce at 300ms

### Command Dispatch

Formatting commands (bold, italic, headings, etc.) use `NotificationCenter` posts from the menu/toolbar, observed by `MarkdownTextView`. This decouples UI triggers from editor logic. All notification names are defined as extensions on `Notification.Name` in `MarksmithApp.swift`.

### Theme System

Editor and preview themes are independent. Each has a three-way setting (System/Light/Dark) stored via `@AppStorage`. `EditorTheme` is a struct with color properties applied to the NSTextView. Preview theme is a CSS class (`light`/`dark`/`auto`) on the `<html>` element, with separate stylesheets for each mode.

### Git Integration

`GitStatusProvider` shells out to `/usr/bin/git` (not a library) to detect repos and parse unified diffs. Line-level statuses feed into `GutterView` for colored indicators. `GitService` handles commit/push operations. Both run on background `DispatchQueue`s.

### SSG Integration

`SSGService` runs build/serve commands as background `Process` instances. It auto-detects localhost URLs from stdout via regex. Preferences store build command, serve command, and optional URL override.

## Key Patterns

- **Regex-based syntax highlighting** in `SyntaxHighlighter` — pattern order matters (fenced code blocks must match before inline patterns to avoid conflicts)
- **All `NSView` subclasses are layer-backed** (`wantsLayer = true`) for GPU compositing
- **Gutter line positioning** uses the layout manager's `lineFragmentRect` to align line numbers with text, recalculated on scroll/layout changes
- **`MarkdownHTMLGenerator`** uses swift-markdown's `MarkupWalker` protocol; the `HTMLRenderer` struct walks the AST and emits HTML with `data-line` attributes for scroll sync
- **Preview resources** (CSS, Prism.js, HTML template) are bundled in `Resources/` and referenced via `Bundle.main.resourceURL`

## Project Configuration

- `project.yml` — XcodeGen spec (target, dependencies, build settings, entitlements)
- `Info.plist` — document type registration for .md/.markdown/.mdown/.mkd
- `Marksmith.entitlements` — sandbox with file access, network client, subprocess execution
