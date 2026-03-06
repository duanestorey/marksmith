# Marksmith

A native macOS Markdown editor with live preview, syntax highlighting, git integration, and static site generator support. Built with SwiftUI and AppKit.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift 5.10](https://img.shields.io/badge/Swift-5.10-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

### Editor
- Monospaced plain-text editing with configurable font size (10–28 pt)
- **Syntax highlighting** for Markdown elements: headings, bold, italic, code, links, images, blockquotes, lists, horizontal rules, and task lists
- **Line number gutter** with accurate positioning for wrapped lines
- **Find bar** (Cmd+F) with incremental search
- Independent light/dark/system theme with full color customization
- Automatic substitutions disabled — no smart quotes or autocorrect interfering with Markdown syntax
- Full undo/redo support

### Live Preview
- GitHub-styled HTML preview rendered in a WebKit view, debounced at 300ms
- **Code syntax highlighting** via Prism.js for 15+ languages (Swift, Python, JavaScript, TypeScript, Go, Rust, Ruby, Java, Bash, JSON, YAML, HTML, CSS, and more)
- **YAML front matter** parsed and rendered as a collapsible key/value table instead of broken Markdown
- Independent light/dark/system theme
- Developer tools available (right-click to Inspect Element)

### Split View
- Horizontal (side by side) or vertical (top and bottom) layout
- Toggle via toolbar button or Cmd+Option+L
- Layout preference persisted across sessions

### Formatting Shortcuts

| Shortcut | Action |
|---|---|
| Cmd+B | **Bold** |
| Cmd+I | *Italic* |
| Cmd+K | Insert link |
| Cmd+Shift+I | Insert image |
| Cmd+Shift+K | Inline code |
| Cmd+Shift+1 | Heading 1 |
| Cmd+Shift+2 | Heading 2 |
| Cmd+Shift+3 | Heading 3 |

All formatting commands are smart: they wrap selected text or insert a placeholder when nothing is selected.

### Git Integration

When the open file is inside a git repository, Marksmith provides:

- **Live gutter indicators** showing added (green), modified (blue), and deleted (red) lines compared to the last commit
- **In-memory diffing** using Swift's `CollectionDifference` (Myers algorithm) — diffs the live buffer against `HEAD` content, debounced at 300ms
- **Auto-refresh on focus** — re-fetches HEAD content when you switch back to the app, picking up external commits
- **Commit sheet** with:
  - Scrollable list of all changed files with colored status labels (Modified, Added, Deleted, Untracked, Renamed)
  - Commit message editor
  - "Stage all changed files" toggle
  - "Push after commit" toggle

No git libraries are used — Marksmith shells out to `/usr/bin/git` directly.

### Static Site Generator (SSG) Integration

Marksmith can build and serve static sites (Hugo, Jekyll, Eleventy, etc.) directly from the editor. Configure commands in **Preferences > SSG**.

**Build** — runs a one-shot command (e.g., `hugo build`) and displays output in a terminal-style panel.

**Serve** — runs a long-running dev server (e.g., `hugo server -D`) with:
- Streaming output in a terminal-style panel (dark background, green monospace text)
- Auto-detection of the localhost URL from server output
- Clickable URLs in the output panel
- Globe button to open the site in your default browser
- Play/stop toggle in the toolbar

**Build output panel** appears as a sub-split inside the editor pane. ANSI escape sequences are automatically stripped from output.

### File Type Registration

Marksmith registers as an editor for `.md`, `.markdown`, `.mdown`, and `.mkd` files. After installation, you can right-click a Markdown file in Finder and choose "Open With > Marksmith", or set it as the default editor.

## Building from Source

### Prerequisites

- **macOS 14 (Sonoma)** or later
- **Xcode 16** or later (install from the Mac App Store or [developer.apple.com](https://developer.apple.com/xcode/))
- **Xcode Command Line Tools** — install with:
  ```bash
  xcode-select --install
  ```
- **Homebrew** — install from [brew.sh](https://brew.sh) if you don't have it

### Setup

1. **Clone the repository:**
   ```bash
   git clone https://github.com/duanestorey/marksmith.git
   cd marksmith
   ```

2. **Install XcodeGen** (one-time):
   ```bash
   make setup
   ```
   This runs `brew install xcodegen`. [XcodeGen](https://github.com/yonaskolb/XcodeGen) generates the Xcode project from `project.yml`, so there's no `.xcodeproj` checked into the repo.

3. **Build the app:**
   ```bash
   make build      # Release build
   # or
   make debug      # Debug build
   ```

   The built app is at `build/Build/Products/{Debug|Release}/Marksmith.app`.

4. **Run it:**
   ```bash
   make run        # Debug build + launch
   ```

5. **Install to /Applications** (optional):
   ```bash
   cp -R build/Build/Products/Release/Marksmith.app /Applications/Marksmith.app
   ```

### All Make Targets

| Command | Description |
|---|---|
| `make setup` | Install XcodeGen via Homebrew |
| `make generate` | Generate `Marksmith.xcodeproj` from `project.yml` |
| `make build` | Release build (generates project first) |
| `make debug` | Debug build |
| `make run` | Debug build + launch the app |
| `make open` | Generate project + open in Xcode |
| `make clean` | Remove `build/` directory and `.xcodeproj` |
| `make all` | Setup + generate + build |

### Opening in Xcode

If you prefer to work in Xcode:

```bash
make open
```

This generates the project and opens it. You can then build and run from Xcode as usual (Cmd+R).

### Dependencies

The only external dependency is [swift-markdown](https://github.com/swiftlang/swift-markdown) (v0.5.0+) for Markdown-to-HTML conversion. It's fetched automatically by Swift Package Manager during the build — no manual dependency installation needed.

## Configuring the SSG Build Pipeline

1. Open **Marksmith > Preferences** (Cmd+,)
2. Go to the **SSG** tab
3. Set your commands:
   - **Build Command**: the command to build your site (e.g., `hugo build`, `jekyll build`, `npx eleventy`)
   - **Serve Command**: the command to start a dev server (e.g., `hugo server -D`, `jekyll serve`, `npx eleventy --serve`)
   - **Override URL** (optional): manually specify the dev server URL if auto-detection doesn't work

Commands run from the **git repository root** of the currently open file. If the file isn't in a git repo, the file's parent directory is used.

### Toolbar Buttons

- **Hammer icon** — runs the build command; output appears in the build output panel
- **Play icon** — starts the dev server; changes to a stop icon while running
- **Globe icon** (appears when server is running) — opens the detected/configured URL in your browser

Both buttons are disabled when their respective commands are empty (not configured) or when no file is open.

## How Git Tracking Works

Marksmith's git integration is designed to show you what you've changed *as you type*, without needing to save first.

### Gutter Indicators

When you open a file that's inside a git repository:

1. Marksmith detects the repo root via `git rev-parse --show-toplevel`
2. It fetches the file's content at HEAD via `git show HEAD:<relative-path>`
3. As you type, it diffs your current buffer against the HEAD content using Swift's `CollectionDifference` (an implementation of the Myers diff algorithm)
4. The diff is debounced at 300ms to avoid excessive computation
5. Results appear as colored bars in the line number gutter:
   - **Green** — new line (added)
   - **Blue** — changed line (modified)
   - **Red triangle** — line was deleted at this position

For **new files** not yet committed, all lines show as added (green).

When you **switch back to Marksmith** from another app, it automatically re-fetches the HEAD content. This means if you commit from the terminal or another tool, the gutter indicators update when you return to Marksmith.

### Committing

Click the **git branch icon** in the toolbar to open the commit sheet. It shows:

- A list of all changed, added, deleted, and untracked files in the repo (via `git status --porcelain`)
- A commit message field
- A toggle to stage all changes (`git add -A`) before committing
- A toggle to push immediately after committing

## Project Structure

```
marksmith/
├── Makefile                    # Build automation
├── project.yml                 # XcodeGen project spec
├── CLAUDE.md                   # AI assistant context
└── Marksmith/
    ├── MarksmithApp.swift      # App entry point, menu commands
    ├── MarkdownDocument.swift  # ReferenceFileDocument model
    ├── Info.plist              # Bundle config, file type registration
    ├── Marksmith.entitlements  # Sandbox entitlements
    ├── Views/
    │   ├── ContentView.swift   # Main split view, toolbar, commit sheet
    │   ├── Editor/
    │   │   ├── EditorView.swift        # NSTextView wrapper + gutter
    │   │   ├── GutterView.swift        # Gutter data model
    │   │   └── SyntaxHighlighter.swift # Regex-based highlighting
    │   ├── Preview/
    │   │   ├── PreviewView.swift           # WKWebView wrapper
    │   │   └── MarkdownHTMLGenerator.swift # AST walker, front matter
    │   └── Preferences/
    │       └── PreferencesView.swift   # General + SSG settings
    ├── Services/
    │   ├── GitStatusProvider.swift  # Git gutter + commit + file status
    │   └── SSGService.swift        # Build/serve process management
    ├── Models/
    │   └── ThemeMode.swift     # System/Light/Dark enum
    └── Resources/
        ├── Assets.xcassets/    # App icon
        ├── preview-template.html
        ├── preview-light.css
        ├── preview-dark.css
        ├── prism.css           # Code highlighting in preview
        └── prism.js
```

## License

Copyright 2026 Duane Storey. All rights reserved.

## Links

- [GitHub Repository](https://github.com/duanestorey/marksmith)
