//
//  WebView.swift
//  TileRate Installation Estimator
//

import SwiftUI
import WebKit

// MARK: - iOS
#if os(iOS)
struct WebView: UIViewRepresentable {

    // If your file name differs, update this list (first that exists will be loaded)
    private let candidateHTMLNames = [
        "index_portrait_step_fit", // you mentioned this one exists
        "index",
        "indexworks"
    ]

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()

        // ✅ Modern way to enable JavaScript (replaces deprecated javaScriptEnabled)
        let webpagePrefs = WKWebpagePreferences()
        webpagePrefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = webpagePrefs

        // Optional: smoother scrolling/zoom behavior
        config.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.bounces = true

        if let url = firstExistingHTMLURL() {
            // Allow reading the whole bundle directory so relative assets load
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            // Fallback message if the HTML can't be found
            let html = """
            <html><head><meta name='viewport' content='width=device-width, initial-scale=1'>
            <style>body{font-family:-apple-system; padding:24px}</style></head>
            <body><h2>index.html not found</h2>
            <p>Place your HTML file in the app bundle and ensure the name matches one of:
            <code>\(candidateHTMLNames.joined(separator: ", "))</code></p></body></html>
            """
            webView.loadHTMLString(html, baseURL: nil)
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    private func firstExistingHTMLURL() -> URL? {
        let bundle = Bundle.main
        for name in candidateHTMLNames {
            if let url = bundle.url(forResource: name, withExtension: "html") {
                return url
            }
        }
        return nil
    }
}
#endif

// MARK: - macOS (if you also build a macOS target)
#if os(macOS)
struct WebView: NSViewRepresentable {

    private let candidateHTMLNames = [
        "index_portrait_step_fit",
        "index",
        "indexworks"
    ]

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()

        // ✅ Modern way to enable JavaScript on macOS as well
        let webpagePrefs = WKWebpagePreferences()
        webpagePrefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = webpagePrefs

        let webView = WKWebView(frame: .zero, configuration: config)

        if let url = firstExistingHTMLURL() {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            let html = """
            <html><head><meta name='viewport' content='width=device-width, initial-scale=1'>
            <style>body{font-family:-apple-system; padding:24px}</style></head>
            <body><h2>index.html not found</h2>
            <p>Place your HTML file in the app bundle and ensure the name matches one of:
            <code>\(candidateHTMLNames.joined(separator: ", "))</code></p></body></html>
            """
            webView.loadHTMLString(html, baseURL: nil)
        }

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    private func firstExistingHTMLURL() -> URL? {
        let bundle = Bundle.main
        for name in candidateHTMLNames {
            if let url = bundle.url(forResource: name, withExtension: "html") {
                return url
            }
        }
        return nil
    }
}
#endif
