import Foundation

/// User-triggered fetch only. Redirects are intentionally refused: a provider
/// URL must not silently transfer a subscription token to another endpoint.
private final class SubscriptionRedirectBlocker: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

enum ProxySubscriptionFetch {
    static func load(_ url: URL, defaultType: ProxyType) async throws -> String {
        // Re-validate so UI callers cannot bypass the source policy.
        guard (try? ProxySubscriptionImport.sourceURL(url.absoluteString)) != nil else {
            throw ProxySubscriptionError.unsafeSource
        }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 25
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.httpMaximumConnectionsPerHost = 1
        let session = URLSession(configuration: config, delegate: SubscriptionRedirectBlocker(),
                                 delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("text/plain, application/json, application/xml, application/octet-stream",
                         forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              (http.expectedContentLength < 0 || http.expectedContentLength <= ProxySubscriptionImport.maxBytes),
              http.url?.host?.lowercased() == url.host?.lowercased(),
              http.url?.scheme?.lowercased() == "https" else {
            throw ProxySubscriptionError.invalidBody
        }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < ProxySubscriptionImport.maxBytes else {
                throw ProxySubscriptionError.oversized
            }
            data.append(byte)
        }
        return try ProxySubscriptionImport.decode(data, defaultType: defaultType)
    }
}
