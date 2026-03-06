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
        context.coordinator.scheduleUpdate(html: html, webView: webView)
    }

    final class Coordinator {
        weak var webView: WKWebView?
        private var debounceTimer: Timer?
        private var lastHTML: String = ""
        private static let debounceInterval: TimeInterval = 0.3

        func scheduleUpdate(html: String, webView: WKWebView) {
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
