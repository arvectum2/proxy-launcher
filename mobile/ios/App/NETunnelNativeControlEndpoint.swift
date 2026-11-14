import Foundation
import NetworkExtension

private final class NativeMessageCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data?, Error>?
    init(_ continuation: CheckedContinuation<Data?, Error>) { self.continuation = continuation }
    func finish(_ result: Result<Data?, Error>) {
        lock.lock(); let c = continuation; continuation = nil; lock.unlock()
        c?.resume(with: result)
    }
}

/// Inactive endpoint for the already-provisioned, explicitly owned lab
/// manager. No manager creation, preference writes or production activation.
@MainActor final class NETunnelNativeControlEndpoint: NativeControlEndpoint {
    let provider: TransportProvider
    private let manager: NETunnelProviderManager
    private let connection: NETunnelProviderSession
    private let marker: String
    private let options: (TransportBackendCoordinator.Session) throws -> [String: NSObject]
    private static let labProviderID = "ru.arvectum.proxylauncher.lab.nativeqa.PacketTunnel"

    init(manager: NETunnelProviderManager, provider: TransportProvider,
         options: @escaping (TransportBackendCoordinator.Session) throws -> [String: NSObject]) throws {
        guard let connection = manager.connection as? NETunnelProviderSession else { throw TransportAdapterError.unreconciled }
        self.manager = manager; self.connection = connection
        self.provider = provider
        self.marker = provider == .rustXray ? "APL isolated synthetic QA v1" : "APL standalone AWG synthetic QA v1"
        self.options = options
        guard owned else { throw TransportAdapterError.unreconciled }
    }
    private var owned: Bool {
        guard let proto = manager.protocolConfiguration as? NETunnelProviderProtocol else { return false }
        return proto.providerBundleIdentifier == Self.labProviderID &&
            proto.providerConfiguration?["labOwner"] as? String == marker &&
            manager.isEnabled && !manager.isOnDemandEnabled && manager.connection === connection
    }
    var status: NativeControlOSStatus {
        guard owned else { return .unknown }
        switch connection.status {
        case .disconnected: return .off
        case .connecting: return .starting
        case .connected: return .connected
        case .disconnecting: return .stopping
        default: return .unknown
        }
    }
    func start(_ session: TransportBackendCoordinator.Session, identity: TransportNativeIdentity) throws {
        guard owned, status == .off, session.plan.provider == provider,
              identity.epoch == session.token.epoch, identity.generation == session.token.generation,
              identity.provider == (provider == .rustXray ? "rust-xray" : "standalone-awg") else { throw TransportAdapterError.unreconciled }
        var values = try options(session)
        guard values["aplNativeIdentity"] == nil else { throw TransportAdapterError.unreconciled }
        values["aplNativeIdentity"] = try TransportNativeCodec.encode(identity) as NSData
        try connection.startTunnel(options: values)
    }
    private func message(_ request: TransportNativeRequest) async throws -> Data? {
        guard owned, status == .connected,
              request.identity.provider == (provider == .rustXray ? "rust-xray" : "standalone-awg") else { throw TransportAdapterError.unreconciled }
        let message = try TransportNativeCodec.encode(request)
        let response: Data? = try await withCheckedThrowingContinuation { continuation in
            let gate = NativeMessageCompletion(continuation)
            do {
                try connection.sendProviderMessage(message) { data in gate.finish(.success(data)) }
            } catch { gate.finish(.failure(error)) }
            DispatchQueue.global().asyncAfter(deadline: .now() + 6) {
                gate.finish(.failure(TransportAdapterError.unreconciled))
            }
        }
        guard owned, status == .connected else { throw TransportAdapterError.unreconciled }
        return response
    }
    func exchange(_ request: TransportNativeRequest) async throws -> TransportNativeResponse {
        guard let response = try await message(request) else { throw TransportAdapterError.unreconciled }
        let value = try TransportNativeCodec.decode(TransportNativeResponse.self,response)
        guard value.matches(request) else { throw TransportAdapterError.unreconciled }
        return value
    }
    // Only a matching explicit provider rejection counts, not nil/timeout/OS failure.
    func rejectsStaleObservation(_ request: TransportNativeRequest) async throws -> Bool {
        guard request.action == .observe else { throw TransportAdapterError.unreconciled }
        return try await exchange(request).state == .rejected
    }
    func stop() throws {
        guard owned else { throw TransportAdapterError.unreconciled }
        connection.stopVPNTunnel()
    }
}
