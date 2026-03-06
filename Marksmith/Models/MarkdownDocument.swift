import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static var markdownText: UTType {
        UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
    }
}

final class MarkdownDocument: ReferenceFileDocument {
    typealias Snapshot = String

    @Published var text: String

    static var readableContentTypes: [UTType] { [.markdownText] }
    static var writableContentTypes: [UTType] { [.markdownText] }

    static let starterContent = """
# Welcome to Marksmith

Start writing your **Markdown** here. The preview will update as you type.

## Features

- Live preview with syntax highlighting
- Light and dark themes
- Git integration
- Keyboard shortcuts for formatting

> Tip: Use **Cmd+B** for bold, **Cmd+I** for italic, and **Cmd+Shift+K** for inline code.
"""

    init(text: String = starterContent) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8)
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = string
    }

    func snapshot(contentType: UTType) throws -> String {
        text
    }

    func fileWrapper(snapshot: String, configuration: WriteConfiguration) throws -> FileWrapper {
        let data = Data(snapshot.utf8)
        return FileWrapper(regularFileWithContents: data)
    }
}
