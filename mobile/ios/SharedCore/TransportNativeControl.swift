import Foundation

enum TransportNativeControlError: Error { case invalidTransition, providerMismatch, staleSession }

/// Secret-free control channel. The provider binds the identity once from
/// the actual start options, never from an incoming status query.
struct TransportNativeIdentity: Codable, Equatable {
    let epoch: UUID
    let generation: UInt64
    let provider: String
    var valid: Bool { generation > 0 && ["rust-xray", "standalone-awg"].contains(provider) }
}

struct TransportNativeRequest: Codable, Equatable {
    enum Action: String, Codable { case observe, drain }
    let version: Int
    let id: UUID
    let identity: TransportNativeIdentity
    let action: Action
    init(identity: TransportNativeIdentity, action: Action) {
        version = 1; id = UUID(); self.identity = identity; self.action = action
    }
    var valid: Bool { version == 1 && identity.valid }
}

struct TransportNativeResponse: Codable, Equatable {
    enum State: String, Codable { case starting, ready, draining, drained, failed }
    let version: Int
    let id: UUID
    let identity: TransportNativeIdentity
    let action: TransportNativeRequest.Action
    let state: State
    init(request: TransportNativeRequest, state: State) {
        version = 1; id = request.id; identity = request.identity; action = request.action; self.state = state
    }
    func matches(_ request: TransportNativeRequest) -> Bool {
        version == 1 && request.valid && id == request.id && identity == request.identity && action == request.action
    }
}

enum TransportNativeCodec {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let data = try JSONEncoder().encode(value)
        guard data.count <= 1024 else { throw TransportNativeControlError.invalidTransition }
        return data
    }
    static func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        guard !data.isEmpty, data.count <= 1024 else { throw TransportNativeControlError.invalidTransition }
        return try JSONDecoder().decode(type, from: data)
    }
}

/// Provider-side state. A drain request never manufactures a drain receipt;
/// the native close and queue retirement must separately finish first.
struct TransportNativeControlState {
    private(set) var identity: TransportNativeIdentity?
    private(set) var state: TransportNativeResponse.State = .starting
    mutating func bind(_ value: TransportNativeIdentity, provider: String) throws {
        guard identity == nil, value.valid, value.provider == provider else { throw TransportNativeControlError.providerMismatch }
        identity = value
    }
    mutating func ready() throws {
        guard identity != nil, state == .starting else { throw TransportNativeControlError.invalidTransition }
        state = .ready
    }
    mutating func beginDrain() throws {
        guard identity != nil, state == .starting || state == .ready || state == .draining else { throw TransportNativeControlError.invalidTransition }
        state = .draining
    }
    mutating func finishDrain() throws {
        guard state == .draining else { throw TransportNativeControlError.invalidTransition }
        state = .drained
    }
    mutating func fail() { state = .failed }
    func response(to request: TransportNativeRequest) throws -> TransportNativeResponse {
        guard request.valid, request.identity == identity else { throw TransportNativeControlError.staleSession }
        return TransportNativeResponse(request: request, state: state)
    }
}
