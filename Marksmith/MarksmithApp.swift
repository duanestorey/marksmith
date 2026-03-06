import SwiftUI
import UniformTypeIdentifiers

@main
struct MarksmithApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: { MarkdownDocument() }) { file in
            ContentView(document: file.document, fileURL: file.fileURL)
        }
        .commands {
            CommandGroup(replacing: .textFormatting) {
                Button("Bold") {
                    NotificationCenter.default.post(name: .editorFormatBold, object: nil)
                }
                .keyboardShortcut("b", modifiers: .command)

                Button("Italic") {
                    NotificationCenter.default.post(name: .editorFormatItalic, object: nil)
                }
                .keyboardShortcut("i", modifiers: .command)

                Button("Code") {
                    NotificationCenter.default.post(name: .editorFormatCode, object: nil)
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])

                Divider()

                Button("Heading 1") {
                    NotificationCenter.default.post(name: .editorFormatH1, object: nil)
                }
                .keyboardShortcut("1", modifiers: [.command, .shift])

                Button("Heading 2") {
                    NotificationCenter.default.post(name: .editorFormatH2, object: nil)
                }
                .keyboardShortcut("2", modifiers: [.command, .shift])

                Button("Heading 3") {
                    NotificationCenter.default.post(name: .editorFormatH3, object: nil)
                }
                .keyboardShortcut("3", modifiers: [.command, .shift])

                Divider()

                Button("Link") {
                    NotificationCenter.default.post(name: .editorFormatLink, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)

                Button("Image") {
                    NotificationCenter.default.post(name: .editorFormatImage, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            }

            CommandGroup(after: .toolbar) {
                Button("Toggle Split Orientation") {
                    NotificationCenter.default.post(name: .toggleSplitOrientation, object: nil)
                }
                .keyboardShortcut("l", modifiers: [.command, .option])
            }
        }

        Settings {
            PreferencesView()
        }
    }
}

extension Notification.Name {
    static let editorFormatBold = Notification.Name("editorFormatBold")
    static let editorFormatItalic = Notification.Name("editorFormatItalic")
    static let editorFormatCode = Notification.Name("editorFormatCode")
    static let editorFormatH1 = Notification.Name("editorFormatH1")
    static let editorFormatH2 = Notification.Name("editorFormatH2")
    static let editorFormatH3 = Notification.Name("editorFormatH3")
    static let editorFormatLink = Notification.Name("editorFormatLink")
    static let editorFormatImage = Notification.Name("editorFormatImage")
    static let toggleSplitOrientation = Notification.Name("toggleSplitOrientation")
}
