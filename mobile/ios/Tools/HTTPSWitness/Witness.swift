import SwiftUI
import Foundation
import CryptoKit

private struct Receipt: Codable {
    let phase: String
    let run: String
    let endpoints: [Result]
    struct Result: Codable {
        let name: String
        let status: Int
        let valid: Bool
        let originDigest: String?
    }
}

private final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@main struct HTTPSWitness: App {
    @State private var status = "Ready — isolated HTTPS witness"
    var body: some Scene { WindowGroup { Text(status).padding().task { await run() } } }
    @MainActor private func run() async {
        let args = ProcessInfo.processInfo.arguments
        guard args.count == 3, let run = UUID(uuidString: args[1]),
              ["direct-before", "tunneled", "direct-after"].contains(args[2]) else { return }
        let phase = args[2]
        status = "Checking HTTPS…"
        async let first = request(name: "httpbingo", run: run, phase: phase)
        async let second = request(name: "ipify", run: run, phase: phase)
        let values = await [first, second]
        let receipt = Receipt(phase: phase, run: run.uuidString, endpoints: values)
        do {
            let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            try JSONEncoder().encode(receipt).write(to: documents.appendingPathComponent("receipt-\(phase).json"), options: .atomic)
            status = "\(phase) — \(values.filter(\.valid).count)/2 valid responses"
        } catch { status = "Receipt write failed" }
    }
    private func request(name: String, run: UUID, phase: String) async -> Receipt.Result {
        let nonce = run.uuidString + "-" + phase
        let uri = name == "httpbingo" ? "https://httpbingo.org/get?qa_nonce=\(nonce)" : "https://api.ipify.org/?format=json&qa_nonce=\(nonce)"
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 8; cfg.timeoutIntervalForResource = 12
        cfg.urlCache = nil; cfg.httpCookieStorage = nil; cfg.urlCredentialStorage = nil
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: cfg, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let (data, response) = try await session.data(from: URL(string: uri)!)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200, data.count <= 32768,
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .init(name: name, status: code, valid: false, originDigest: nil) }
            let origin: String?
            if name == "httpbingo" {
                guard let query = object["args"] as? [String: [String]], query["qa_nonce"] == [nonce] else { return .init(name: name, status: code, valid: false, originDigest: nil) }
                origin = object["origin"] as? String
            } else { origin = object["ip"] as? String }
            guard let origin, !origin.isEmpty, origin.utf8.count <= 256 else { return .init(name: name, status: code, valid: false, originDigest: nil) }
            let digest = SHA256.hash(data: Data((run.uuidString + "|" + origin).utf8)).map { String(format: "%02x", $0) }.joined()
            return .init(name: name, status: code, valid: true, originDigest: digest)
        } catch { return .init(name: name, status: (error as NSError).code, valid: false, originDigest: nil) }
    }
}
