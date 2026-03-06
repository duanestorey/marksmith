import SwiftUI

struct ContentView: View {
    @ObservedObject var document: MarkdownDocument

    @AppStorage("splitOrientation") private var isVerticalSplit = false
    @AppStorage("editorThemeMode") private var editorThemeMode: ThemeMode = .system
    @AppStorage("previewThemeMode") private var previewThemeMode: ThemeMode = .system
    @AppStorage("fontSize") private var fontSize: Double = 14

    @State private var previewHTML: String = ""
    @State private var gitStatuses: [Int: GitLineStatus] = [:]
    @State private var showCommitSheet = false
    @State private var ssgRunning = false

    @Environment(\.undoManager) var undoManager
    @Environment(\.colorScheme) var systemColorScheme

    private let htmlGenerator = MarkdownHTMLGenerator()

    var editorTheme: EditorTheme {
        let isDark: Bool
        switch editorThemeMode {
        case .system: isDark = systemColorScheme == .dark
        case .light: isDark = false
        case .dark: isDark = true
        }
        let base = isDark ? EditorTheme.dark : EditorTheme.light
        // Apply user font size
        return EditorTheme(
            backgroundColor: base.backgroundColor,
            textColor: base.textColor,
            cursorColor: base.cursorColor,
            selectionColor: base.selectionColor,
            fontSize: CGFloat(fontSize),
            headingColor: base.headingColor,
            boldColor: base.boldColor,
            italicColor: base.italicColor,
            codeColor: base.codeColor,
            linkColor: base.linkColor,
            linkURLColor: base.linkURLColor,
            blockQuoteColor: base.blockQuoteColor,
            listMarkerColor: base.listMarkerColor
        )
    }

    var previewTheme: PreviewTheme {
        switch previewThemeMode {
        case .system: return .system
        case .light: return .light
        case .dark: return .dark
        }
    }

    var body: some View {
        Group {
            if isVerticalSplit {
                VSplitView {
                    editorPane
                    previewPane
                }
            } else {
                HSplitView {
                    editorPane
                    previewPane
                }
            }
        }
        .toolbar {
            toolbarContent
        }
        .onAppear {
            updatePreview()
        }
        .onChange(of: document.text) { _ in
            updatePreview()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleSplitOrientation)) { _ in
            isVerticalSplit.toggle()
        }
        .sheet(isPresented: $showCommitSheet) {
            CommitSheetView(document: document)
        }
    }

    private var editorPane: some View {
        EditorView(
            document: document,
            theme: editorTheme,
            gitStatuses: gitStatuses
        )
        .frame(minWidth: 200, minHeight: 150)
    }

    private var previewPane: some View {
        PreviewView(
            html: previewHTML,
            theme: previewTheme,
            baseURL: nil
        )
        .frame(minWidth: 200, minHeight: 150)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            // Split orientation toggle
            Button(action: { isVerticalSplit.toggle() }) {
                Image(systemName: isVerticalSplit
                      ? "rectangle.split.1x2"
                      : "rectangle.split.2x1")
            }
            .help(isVerticalSplit ? "Switch to horizontal split" : "Switch to vertical split")

            Divider()

            // Editor theme
            Menu {
                ForEach(ThemeMode.allCases, id: \.self) { mode in
                    Button(action: { editorThemeMode = mode }) {
                        HStack {
                            Text(mode.label)
                            if editorThemeMode == mode {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "textformat")
            }
            .help("Editor theme")

            // Preview theme
            Menu {
                ForEach(ThemeMode.allCases, id: \.self) { mode in
                    Button(action: { previewThemeMode = mode }) {
                        HStack {
                            Text(mode.label)
                            if previewThemeMode == mode {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "eye")
            }
            .help("Preview theme")

            Divider()

            // Git commit
            Button(action: { showCommitSheet = true }) {
                Image(systemName: "arrow.triangle.branch")
            }
            .help("Commit & Push")
        }
    }

    private func updatePreview() {
        let text = document.text
        DispatchQueue.global(qos: .userInitiated).async {
            let html = htmlGenerator.generateFullPage(from: text, theme: previewTheme)
            DispatchQueue.main.async {
                previewHTML = html
            }
        }
    }
}

enum ThemeMode: String, CaseIterable {
    case system
    case light
    case dark

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

// MARK: - Commit Sheet

struct CommitSheetView: View {
    @ObservedObject var document: MarkdownDocument
    @Environment(\.dismiss) var dismiss

    @State private var commitMessage = ""
    @State private var pushAfterCommit = true
    @State private var isCommitting = false
    @State private var statusMessage = ""
    @State private var stageAllFiles = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Commit Changes")
                .font(.headline)

            TextEditor(text: $commitMessage)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 80)
                .border(Color.secondary.opacity(0.3))
                .overlay(
                    Group {
                        if commitMessage.isEmpty {
                            Text("Enter commit message...")
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .allowsHitTesting(false)
                        }
                    },
                    alignment: .topLeading
                )

            Toggle("Stage all changed files", isOn: $stageAllFiles)
            Toggle("Push after commit", isOn: $pushAfterCommit)

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundColor(statusMessage.contains("Error") ? .red : .secondary)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Commit") {
                    performCommit()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(commitMessage.isEmpty || isCommitting)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func performCommit() {
        isCommitting = true
        statusMessage = "Committing..."

        GitService.shared.commit(
            message: commitMessage,
            stageAll: stageAllFiles,
            push: pushAfterCommit
        ) { result in
            DispatchQueue.main.async {
                isCommitting = false
                switch result {
                case .success:
                    statusMessage = "Committed successfully!"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        dismiss()
                    }
                case .failure(let error):
                    statusMessage = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
}
