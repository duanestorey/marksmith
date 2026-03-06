import SwiftUI

struct ContentView: View {
    @ObservedObject var document: MarkdownDocument
    var fileURL: URL?

    @AppStorage("splitOrientation") private var isVerticalSplit = false
    @AppStorage("editorThemeMode") private var editorThemeMode: ThemeMode = .system
    @AppStorage("previewThemeMode") private var previewThemeMode: ThemeMode = .system
    @AppStorage("fontSize") private var fontSize: Double = 14
    @AppStorage("ssgBuildCommand") private var ssgBuildCommand = ""
    @AppStorage("ssgServeCommand") private var ssgServeCommand = ""
    @AppStorage("ssgServeURL") private var ssgServeURL = ""

    @StateObject private var gitStatus = GitStatusProvider()
    @StateObject private var ssgService = SSGService()

    @State private var previewHTML: String = ""
    @State private var showCommitSheet = false
    @State private var showBuildOutput = false
    @State private var buildOutputText = ""
    @State private var buildOutputTitle = "Build Output"

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

    private var repoRootPath: String? {
        gitStatus.repoRoot?.path
    }

    private var hasSSGBuild: Bool {
        !ssgBuildCommand.isEmpty && fileURL != nil
    }

    private var hasSSGServe: Bool {
        !ssgServeCommand.isEmpty && fileURL != nil
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
            gitStatus.configure(fileURL: fileURL)
            updatePreview()
            gitStatus.diffBuffer(document.text)
        }
        .onChange(of: document.text) {
            updatePreview()
            gitStatus.diffBuffer(document.text)
        }
        .onChange(of: previewThemeMode) {
            updatePreview()
        }
        .onChange(of: systemColorScheme) {
            updatePreview()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleSplitOrientation)) { _ in
            isVerticalSplit.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            gitStatus.refetchHEAD()
            gitStatus.diffBuffer(document.text)
        }
        .onReceive(ssgService.$output) { output in
            if showBuildOutput {
                buildOutputText = output
            }
        }
        .sheet(isPresented: $showCommitSheet) {
            CommitSheetView(document: document, repoRoot: repoRootPath)
        }
    }

    private var editorPane: some View {
        Group {
            if showBuildOutput {
                if isVerticalSplit {
                    // Vertical split: editor pane becomes HSplitView (editor left, output right)
                    HSplitView {
                        editorContent
                        buildOutputPanel
                    }
                } else {
                    // Horizontal split: editor pane becomes VSplitView (editor top, output bottom)
                    VSplitView {
                        editorContent
                        buildOutputPanel
                    }
                }
            } else {
                editorContent
            }
        }
        .frame(minWidth: 200, minHeight: 150)
    }

    private var editorContent: some View {
        EditorView(
            document: document,
            theme: editorTheme,
            gitStatuses: gitStatus.lineStatuses
        )
        .frame(minWidth: 200, minHeight: 100)
    }

    private var buildOutputPanel: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Text(buildOutputTitle)
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.medium)

                Spacer()

                // Open URL in browser (only when serving)
                if case .running(let url) = ssgService.status {
                    Button(action: {
                        if let nsURL = URL(string: url) {
                            NSWorkspace.shared.open(nsURL)
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "globe")
                            Text(url)
                        }
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.blue)
                    }
                    .buttonStyle(.borderless)
                    .help("Open \(url) in browser")
                }

                // Close button
                Button(action: {
                    showBuildOutput = false
                    ssgService.stop()
                }) {
                    Image(systemName: "xmark")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Close output panel")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Terminal-style output
            ScrollViewReader { proxy in
                ScrollView {
                    Text(attributedBuildOutput(buildOutputText))
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .id("outputBottom")
                }
                .background(Color(nsColor: NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)))
                .onChange(of: buildOutputText) {
                    proxy.scrollTo("outputBottom", anchor: .bottom)
                }
            }
        }
        .frame(minWidth: 150, minHeight: 80)
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

            // SSG Build
            Button(action: { performSSGBuild() }) {
                Image(systemName: "hammer")
            }
            .help("Build site")
            .disabled(!hasSSGBuild)

            // SSG Serve toggle
            Button(action: { toggleSSGServe() }) {
                Image(systemName: ssgService.status.isRunning ? "stop.fill" : "play.fill")
            }
            .help(ssgService.status.isRunning ? "Stop server" : "Start server")
            .disabled(!hasSSGServe)

            Divider()

            // Git commit
            Button(action: { showCommitSheet = true }) {
                Image(systemName: "arrow.triangle.branch")
            }
            .help("Commit & Push")
            .disabled(!gitStatus.isGitRepo)
        }
    }

    private func attributedBuildOutput(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        result.foregroundColor = .green

        // Find URLs and make them clickable
        let urlPattern = try! NSRegularExpression(
            pattern: #"https?://[^\s]+"#,
            options: .caseInsensitive
        )
        let nsText = text as NSString
        let matches = urlPattern.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        for match in matches {
            guard let swiftRange = Range(match.range, in: text) else { continue }
            let urlString = String(text[swiftRange])
            guard let url = URL(string: urlString) else { continue }

            if let attrRange = Range(swiftRange, in: result) {
                result[attrRange].link = url
                result[attrRange].foregroundColor = .cyan
                result[attrRange].underlineStyle = .single
            }
        }

        return result
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

    private func performSSGBuild() {
        guard let repoRoot = repoRootPath else { return }
        buildOutputTitle = "Build Output"
        buildOutputText = "Running: \(ssgBuildCommand)\n\n"
        showBuildOutput = true

        ssgService.build(command: ssgBuildCommand, workingDirectory: repoRoot) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let output):
                    buildOutputText += output + "\n\nBuild completed successfully."
                case .failure(let error):
                    buildOutputText += "\nBuild failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func toggleSSGServe() {
        guard let repoRoot = repoRootPath else { return }
        if ssgService.status.isRunning {
            ssgService.stop()
            showBuildOutput = false
        } else {
            buildOutputTitle = "Server Output"
            buildOutputText = ""
            showBuildOutput = true
            ssgService.serve(
                command: ssgServeCommand,
                workingDirectory: repoRoot,
                configuredURL: ssgServeURL.isEmpty ? nil : ssgServeURL
            )
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
    var repoRoot: String?
    @Environment(\.dismiss) var dismiss

    @State private var commitMessage = ""
    @State private var pushAfterCommit = true
    @State private var isCommitting = false
    @State private var statusMessage = ""
    @State private var stageAllFiles = false
    @State private var fileStatuses: [GitFileStatus] = []
    @State private var isLoadingFiles = true

    var body: some View {
        VStack(spacing: 16) {
            Text("Commit Changes")
                .font(.headline)

            // File list
            VStack(alignment: .leading, spacing: 4) {
                Text("Changed Files")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if isLoadingFiles {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 60)
                } else if fileStatuses.isEmpty {
                    Text("No changes detected")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 60)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(fileStatuses) { file in
                                HStack(spacing: 8) {
                                    Text(file.displayStatus)
                                        .font(.system(.caption, design: .monospaced))
                                        .fontWeight(.medium)
                                        .foregroundColor(colorForStatus(file.statusCode))
                                        .frame(width: 70, alignment: .leading)

                                    Text(file.filePath)
                                        .font(.system(.caption, design: .monospaced))
                                        .lineLimit(1)
                                        .truncationMode(.middle)

                                    Spacer()
                                }
                                .padding(.vertical, 2)
                                .padding(.horizontal, 4)
                            }
                        }
                    }
                    .frame(maxHeight: 150)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.secondary.opacity(0.3))
                    )
                }
            }

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
        .frame(width: 480)
        .onAppear {
            loadFileStatuses()
        }
    }

    private func colorForStatus(_ code: String) -> Color {
        switch code {
        case "M": return .blue
        case "A": return .green
        case "D": return .red
        case "??": return .secondary
        default: return .secondary
        }
    }

    private func loadFileStatuses() {
        guard let root = repoRoot else {
            isLoadingFiles = false
            return
        }
        GitService.shared.status(repoRoot: root) { files in
            fileStatuses = files
            isLoadingFiles = false
        }
    }

    private func performCommit() {
        isCommitting = true
        statusMessage = "Committing..."

        GitService.shared.commit(
            message: commitMessage,
            stageAll: stageAllFiles,
            push: pushAfterCommit,
            repoRoot: repoRoot
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
