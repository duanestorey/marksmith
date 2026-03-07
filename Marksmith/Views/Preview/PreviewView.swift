import SwiftUI
import WebKit

struct PreviewView: NSViewRepresentable {
    let html: String
    let theme: PreviewTheme
    let baseURL: URL?
    var scrollToLine: Int = 0
    var onScrollLineChange: ((Int) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        // Scroll sync: add message handler for scroll position reports from JS
        let weakHandler = WeakScriptMessageHandler(delegate: context.coordinator)
        config.userContentController.add(weakHandler, name: "scrollSync")

        // Inject scroll position reporter (WKUserScript runs even with allowsContentJavaScript=false)
        let scrollScript = WKUserScript(source: """
            var _scrollSyncTimer = null;
            window.addEventListener('scroll', function() {
                if (_scrollSyncTimer) clearTimeout(_scrollSyncTimer);
                _scrollSyncTimer = setTimeout(function() {
                    var els = document.querySelectorAll('[data-line]');
                    for (var i = 0; i < els.length; i++) {
                        if (els[i].getBoundingClientRect().top >= 0) {
                            window.webkit.messageHandlers.scrollSync.postMessage(
                                parseInt(els[i].dataset.line)
                            );
                            return;
                        }
                    }
                }, 100);
            });
        """, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        config.userContentController.addUserScript(scrollScript)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.wantsLayer = true
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView

        // Load initial HTML
        let resourceURL = Bundle.main.resourceURL ?? Bundle.main.bundleURL
        webView.loadHTMLString(html, baseURL: resourceURL)

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onScrollLineChange = onScrollLineChange
        context.coordinator.scheduleUpdate(html: html, webView: webView)
        context.coordinator.updateScrollToLine(scrollToLine)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        weak var webView: WKWebView?
        var onScrollLineChange: ((Int) -> Void)?
        private var debounceTimer: Timer?
        private var lastHTML: String = ""
        private var lastScrollToLine: Int = 0
        private var pendingScrollToLine: Int = 0
        private var isLoadingContent: Bool = false
        private var isProgrammaticScroll: Bool = false
        private static let debounceInterval: TimeInterval = 0.3

        func scheduleUpdate(html: String, webView: WKWebView) {
            guard html != lastHTML else { return }
            lastHTML = html
            isLoadingContent = true

            debounceTimer?.invalidate()
            debounceTimer = Timer.scheduledTimer(withTimeInterval: Self.debounceInterval, repeats: false) { [weak webView] _ in
                guard let webView = webView else { return }
                let resourceURL = Bundle.main.resourceURL ?? Bundle.main.bundleURL
                webView.loadHTMLString(html, baseURL: resourceURL)
            }
        }

        func updateScrollToLine(_ line: Int) {
            pendingScrollToLine = line
            guard !isLoadingContent, let webView = webView else { return }
            guard line > 0, line != lastScrollToLine else { return }
            lastScrollToLine = line
            scrollPreviewToLine(line, in: webView)
        }

        private func scrollPreviewToLine(_ line: Int, in webView: WKWebView) {
            isProgrammaticScroll = true
            // Find the closest data-line element at or before the target line
            let js = """
            (function(){
                var t=\(line);var b=null;
                document.querySelectorAll('[data-line]').forEach(function(e){
                    if(parseInt(e.dataset.line)<=t)b=e
                });
                if(b)b.scrollIntoView({block:'start'})
            })()
            """
            webView.evaluateJavaScript(js) { [weak self] _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self?.isProgrammaticScroll = false
                }
            }
        }

        // MARK: - WKNavigationDelegate

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Restore scroll position after content reload
            if pendingScrollToLine > 0 {
                let line = pendingScrollToLine
                lastScrollToLine = line
                isProgrammaticScroll = true
                let js = """
                (function(){
                    var t=\(line);var b=null;
                    document.querySelectorAll('[data-line]').forEach(function(e){
                        if(parseInt(e.dataset.line)<=t)b=e
                    });
                    if(b)b.scrollIntoView({block:'start'})
                })()
                """
                webView.evaluateJavaScript(js) { [weak self] _, _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self?.isLoadingContent = false
                        self?.isProgrammaticScroll = false
                    }
                }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    self?.isLoadingContent = false
                }
            }
        }

        // MARK: - WKScriptMessageHandler

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard !isLoadingContent, !isProgrammaticScroll else { return }
            if message.name == "scrollSync", let line = message.body as? Int, line > 0 {
                onScrollLineChange?(line)
            }
        }
    }
}

// MARK: - Weak wrapper to avoid retain cycle with WKUserContentController

private class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}
