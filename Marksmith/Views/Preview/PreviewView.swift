import SwiftUI
import WebKit

struct PreviewView: NSViewRepresentable {
    let html: String
    let theme: PreviewTheme
    let baseURL: URL?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.wantsLayer = true
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.webView = webView

        // Load initial HTML
        let resourceURL = Bundle.main.resourceURL ?? Bundle.main.bundleURL
        webView.loadHTMLString(html, baseURL: resourceURL)

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Update theme class without full reload
        let themeClass = theme == .dark ? "dark" : theme == .light ? "light" : "auto"
        let setThemeJS = "document.documentElement.className = '\(themeClass)';"

        // Update content with debounce
        context.coordinator.scheduleUpdate(html: html, themeJS: setThemeJS, webView: webView)
    }

    final class Coordinator {
        weak var webView: WKWebView?
        private var debounceTimer: Timer?
        private var lastHTML: String = ""
        private static let debounceInterval: TimeInterval = 0.3

        func scheduleUpdate(html: String, themeJS: String, webView: WKWebView) {
            // Apply theme immediately
            webView.evaluateJavaScript(themeJS) { _, _ in }

            // Debounce content updates
            guard html != lastHTML else { return }
            lastHTML = html

            debounceTimer?.invalidate()
            debounceTimer = Timer.scheduledTimer(withTimeInterval: Self.debounceInterval, repeats: false) { [weak webView] _ in
                guard let webView = webView else { return }
                let resourceURL = Bundle.main.resourceURL ?? Bundle.main.bundleURL
                webView.loadHTMLString(html, baseURL: resourceURL)
            }
        }
    }
}
