//  WebVerifier.swift
//  KaiKlok
//
//  Created by BJ Klock on 9/13/25.
//

import WebKit
import SwiftUI

/// Run all WebKit work on the main actor.
@MainActor
final class WebVerifier: NSObject, WKScriptMessageHandler, WKNavigationDelegate {

    private var webView: WKWebView!
    private var verifyContinuation: CheckedContinuation<Bool, Never>?
    private var loadContinuation: CheckedContinuation<Void, Never>?
    private var isLoaded = false

    override init() {
        super.init() // ✅ call super before using `self`

        let cfg = WKWebViewConfiguration()
        cfg.userContentController.add(self, name: "sigilVerified")

        webView = WKWebView(frame: .zero, configuration: cfg)
        webView.navigationDelegate = self
        webView.isHidden = true

        // Load bundled verifier HTML (add to Copy Bundle Resources)
        if let url = Bundle.main.url(forResource: "verifier.inline", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }

    deinit {
        // ❗️Don't touch WebKit from a nonisolated deinit. Schedule cleanup on the main actor.
        Task { @MainActor [weak self] in
            guard let self, let webView = self.webView else { return }
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "sigilVerified")
            webView.navigationDelegate = nil
        }
    }

    // MARK: - Public API

    /// Explicit cleanup to break the WKUserContentController ↔ handler retain cycle.
    func teardown() {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "sigilVerified")
        webView.navigationDelegate = nil
    }

    /// Ensures the verifier page is loaded before evaluating JS.
    private func ensureLoaded() async {
        if isLoaded { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            loadContinuation = cont
        }
    }

    /// Pass pre-serialized JSON objects as strings (e.g. "{\"a\":1}")
    /// They are injected as raw objects into JS (no quotes added).
    func verify(proofJSON: String, publicSignalsJSON: String) async -> Bool {
        await ensureLoaded()

        // Build JS call safely. Assumes `window.verifySigil(obj, obj)` is defined by your page.
        let js =
        """
        (function(){
          try {
            const proof = \(proofJSON);
            const pub   = \(publicSignalsJSON);
            return window.verifySigil(proof, pub)
              .then(r => { window.webkit.messageHandlers.sigilVerified.postMessage(!!r); })
              .catch(_ => { window.webkit.messageHandlers.sigilVerified.postMessage(false); });
          } catch(e) {
            window.webkit.messageHandlers.sigilVerified.postMessage(false);
          }
        })();
        """

        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            self.verifyContinuation = cont
            self.webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoaded = true
        loadContinuation?.resume()
        loadContinuation = nil
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "sigilVerified" else { return }
        let ok = (message.body as? Bool) ?? false
        verifyContinuation?.resume(returning: ok)
        verifyContinuation = nil
    }
}
