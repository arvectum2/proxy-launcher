import Foundation
import UIKit
import WebKit

struct SiteScanObservation {
    let html: [String]
    let network: [String]
    let external: [String]
}

/// Ephemeral WebKit scanner; no persistent cookies or implicit VPN changes.
@MainActor
final class ExclusionWebScanner: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var completion: ((Result<SiteScanObservation, Error>) -> Void)?
    private var host = ""

    func scan(host: String, completion: @escaping (Result<SiteScanObservation, Error>) -> Void) {
        self.host = host
        self.completion = completion
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: CGRect(x: -1, y: -1, width: 1, height: 1), configuration: configuration)
        // WebKit may defer navigation for an unattached zero-sized web view.
        view.isUserInteractionEnabled = false
        view.alpha = 0.01
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })?
            .addSubview(view)
        webView = view
        view.navigationDelegate = self
        guard let url = URL(string: "https://" + host) else { finish(.failure(URLError(.badURL))); return }
        view.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15))
        DispatchQueue.main.asyncAfter(deadline: .now() + 18) { [weak self] in
            self?.finish(.failure(URLError(.timedOut)))
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let destination = navigationAction.request.url,
              destination.scheme?.lowercased() == "https",
              let requested = URL(string: "https://" + host)?.host?.lowercased(),
              destination.host?.lowercased() == requested else {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func cancel() {
        completion = nil
        tearDownWebView()
    }

    private func tearDownWebView() {
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.removeFromSuperview()
        webView = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let script = """
        JSON.stringify({html: document.documentElement.outerHTML.slice(0,512000),
          resources: performance.getEntriesByType('resource').slice(0,512).map(x => x.name)})
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            if let error { self.finish(.failure(error)); return }
            guard let raw = (value as? String)?.data(using: .utf8),
                  let payload = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any] else {
                self.finish(.failure(URLError(.cannotParseResponse)))
                return
            }
            let html = payload["html"] as? String ?? ""
            let resources = payload["resources"] as? [String] ?? []
            let htmlHosts = SiteDependencyDiscovery.candidates(html: html, for: self.host)
            let networkHosts = SiteDependencyDiscovery.resourceCandidates(urls: resources, for: self.host)
            let external = SiteDependencyDiscovery.externalCandidates(urls: resources, for: self.host)
            self.finish(.success(SiteScanObservation(html: htmlHosts, network: networkHosts, external: external)))
        }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }
    private func finish(_ result: Result<SiteScanObservation, Error>) {
        guard let completion else { return }
        self.completion = nil
        tearDownWebView()
        completion(result)
    }
}
