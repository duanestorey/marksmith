import SwiftUI

struct PreferencesView: View {
    var body: some View {
        TabView {
            GeneralPreferencesView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            SSGPreferencesView()
                .tabItem {
                    Label("SSG", systemImage: "server.rack")
                }
        }
        .frame(width: 480, height: 360)
    }
}

struct GeneralPreferencesView: View {
    @AppStorage("fontSize") private var fontSize: Double = 14
    @AppStorage("editorThemeMode") private var editorThemeMode: ThemeMode = .system
    @AppStorage("previewThemeMode") private var previewThemeMode: ThemeMode = .system
    @AppStorage("splitOrientation") private var isVerticalSplit = false
    @AppStorage("spellCheckEnabled") private var spellCheckEnabled = true
    @AppStorage("grammarCheckEnabled") private var grammarCheckEnabled = false
    @AppStorage("spellingLanguage") private var spellingLanguage: SpellingLanguage = .automatic

    var body: some View {
        Form {
            Section("Editor") {
                HStack {
                    Text("Font Size")
                    Spacer()
                    Slider(value: $fontSize, in: 10...28, step: 1) {
                        Text("Font Size")
                    }
                    .frame(width: 200)
                    Text("\(Int(fontSize)) pt")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }

                Picker("Editor Theme", selection: $editorThemeMode) {
                    ForEach(ThemeMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
            }

            Section("Preview") {
                Picker("Preview Theme", selection: $previewThemeMode) {
                    ForEach(ThemeMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
            }

            Section("Layout") {
                Picker("Default Split", selection: $isVerticalSplit) {
                    Text("Horizontal (side by side)").tag(false)
                    Text("Vertical (top and bottom)").tag(true)
                }
            }

            Section("Spelling & Grammar") {
                Toggle("Check spelling while typing", isOn: $spellCheckEnabled)

                Toggle("Check grammar", isOn: $grammarCheckEnabled)

                Picker("Language", selection: $spellingLanguage) {
                    ForEach(SpellingLanguage.allCases, id: \.self) { lang in
                        Text(lang.label).tag(lang)
                    }
                }
            }
        }
        .padding(20)
    }
}

struct SSGPreferencesView: View {
    @AppStorage("ssgBuildCommand") private var buildCommand = ""
    @AppStorage("ssgServeCommand") private var serveCommand = ""
    @AppStorage("ssgServeURL") private var serveURL = ""

    var body: some View {
        Form {
            Section("Build") {
                TextField("Build Command", text: $buildCommand, prompt: Text("e.g., hugo build"))
                Text("Command to build the static site")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Serve") {
                TextField("Serve Command", text: $serveCommand, prompt: Text("e.g., hugo server -D"))
                Text("Command to start the dev server. The URL will be auto-detected from output.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField("Override URL", text: $serveURL, prompt: Text("e.g., http://localhost:1313"))
                Text("Optional. Override the auto-detected serve URL.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                Text("Commands run from the project root (detected via git or file location).")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
    }
}

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
