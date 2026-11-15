import Foundation

/// Separate compile-only synthetic mode. No persisted record, ticket or
/// application-controlled routing policy is accepted by this envelope.
struct NativeSyntheticRuntimeRequest: CustomStringConvertible, CustomReflectable {
    static let mode="synthetic-runtime-v1"
    static let fixtureKey="aplNativeSyntheticFixture"
    static let localKey="aplNativeSyntheticLocalIPv4"
    let owner:UUID
    let binding:NativeCredentialHandoff.Binding
    let fixture:Data
    let localIPv4:UInt32?
    var description:String {"NativeSyntheticRuntimeRequest(redacted)"}
    var customMirror:Mirror {Mirror(self,children:[:])}
    static func configuration(owner:UUID)->[String:String] {
        [NativeProviderStartRequest.modeKey:mode,NativeProviderStartRequest.ownerKey:owner.uuidString]
    }
    static func inspect(configuration:[String:Any]?,options:[String:NSObject]?,provider:TransportProvider)->Self? {
        let mk=NativeProviderStartRequest.modeKey,ok=NativeProviderStartRequest.ownerKey,ek=NativeProviderStartRequest.expectedKey
        guard let config=configuration,let opts=options,Set(config.keys)==[mk,ok],config[mk] as? String==mode,
              let text=config[ok] as? String,let owner=UUID(uuidString:text),text==owner.uuidString,
              opts[mk] as? String==mode,opts[ok] as? String==text,
              let bytes=opts[ek] as? Data,let binding=try? TransportNativeCodec.decode(NativeCredentialHandoff.Binding.self,bytes),
              binding.valid,binding.reference.kind.provider==provider,let fixture=opts[fixtureKey] as? Data else{return nil}
        if provider == .standaloneAWG {
            guard Set(opts.keys)==[mk,ok,ek,fixtureKey,localKey],fixture.count==96,
                  let local=opts[localKey] as? String,let ip=UInt32(local),String(ip)==local,
                  ip>>8==0xc0a801,(1...254).contains(ip&255),ip&255 != 80 else{return nil}
            return .init(owner:owner,binding:binding,fixture:fixture,localIPv4:ip)
        }
        guard Set(opts.keys)==[mk,ok,ek,fixtureKey],!fixture.isEmpty,fixture.count<=4096,
              String(data:fixture,encoding:.utf8) != nil else{return nil}
        return .init(owner:owner,binding:binding,fixture:fixture,localIPv4:nil)
    }
}
