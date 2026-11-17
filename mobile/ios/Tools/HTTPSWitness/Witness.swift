import SwiftUI
import Foundation
import CryptoKit
import Network

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
        if args.count == 4, let run = UUID(uuidString: args[1]), args[2] == "native-tcp4",
           args[3].count == 40, args[3].allSatisfy({ "0123456789abcdef".contains($0) }) {
            status = "Checking isolated TCP witness…"
            let ok = await TCPWitness.probe(nonce: args[3])
            let receipt = NativeReceipt(run: run.uuidString, nonceDigest: SHA256.hash(data: Data(args[3].utf8)).map { String(format: "%02x", $0) }.joined(), valid: ok)
            do {
                let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                try JSONEncoder().encode(receipt).write(to: documents.appendingPathComponent("receipt-native-tcp4.json"), options: .atomic)
                status = ok ? "Native exact TCP receipt — PASS" : "Native exact TCP receipt — FAIL"
            } catch { status = "Receipt write failed" }
            return
        }
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

private struct NativeReceipt: Codable {
    let run: String
    let nonceDigest: String
    let valid: Bool
}

private final class TCPWitness {
    private let queue = DispatchQueue(label: "apl.httpswitness.native")
    private let connection = NWConnection(host: "198.51.100.77", port: 39883, using: .tcp)
    private var response = Data()
    private var complete: ((Bool) -> Void)?
    private let nonce: String
    private init(nonce: String) { self.nonce = nonce }
    static func probe(nonce: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let w = TCPWitness(nonce: nonce)
            w.complete = { continuation.resume(returning: $0) }
            w.queue.asyncAfter(deadline: .now() + 9) { w.finish(false) }
            w.connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let request = Data("GET /\(nonce) HTTP/1.1\r\nHost: 198.51.100.77:39883\r\nConnection: close\r\n\r\n".utf8)
                    w.connection.send(content: request, completion: .contentProcessed { err in
                        if err != nil { w.finish(false) } else { w.receive() }
                    })
                case .failed, .cancelled: w.finish(false)
                default: break
                }
            }
            w.connection.start(queue: w.queue)
        }
    }
    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 2048) { data, _, ended, err in
            guard self.complete != nil else { return }
            if let data { self.response.append(data) }
            guard self.response.count <= 4096 else { self.finish(false); return }
            let text = String(data: self.response, encoding: .utf8) ?? ""
            if let end = text.range(of: "\r\n\r\n"), text.hasPrefix("HTTP/1.1 200 OK\r\n"), String(text[end.upperBound...]) == "APL_RECEIPT:" + self.nonce {
                self.finish(true)
            } else if ended || err != nil { self.finish(false) }
            else { self.receive() }
        }
    }
    private func finish(_ ok: Bool) {
        guard let done = complete else { return }; complete = nil
        connection.stateUpdateHandler = nil; connection.cancel(); done(ok)
    }
}
