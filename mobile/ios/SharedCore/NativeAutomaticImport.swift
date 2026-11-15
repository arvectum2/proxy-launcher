import Foundation

/// Bounded all-or-nothing native import, without protocol guessing or fallback.
/// One WG/AWG configuration per source; one or more VLESS URIs per source.
/// Raw input and credentials never become presentation metadata.
enum NativeAutomaticImport {
    static let maxBytes=512*1024
    static let maxSources=NativeProfileBackupCodec.maxProfiles
    enum Failure:Error,Equatable {case empty,tooLarge,unsupported,duplicate}
    static func readSource(_ url:URL,limit:Int)throws->String {
        guard url.isFileURL,limit>0,limit<=maxBytes else{throw Failure.tooLarge}
        let access=url.startAccessingSecurityScopedResource();defer{if access{url.stopAccessingSecurityScopedResource()}}
        let handle=try FileHandle(forReadingFrom:url);defer{try? handle.close()};var data=Data()
        while data.count<=limit {
            let part=try handle.read(upToCount:limit+1-data.count) ?? Data()
            if part.isEmpty{break};data.append(part)
        }
        guard data.count<=limit else{throw Failure.tooLarge}
        guard let source=String(data:data,encoding:.utf8),!source.isEmpty else{throw Failure.unsupported}
        return source
    }
    static func readSources(_ urls:[URL])throws->[String] {
        guard !urls.isEmpty else{throw Failure.empty}
        guard urls.count<=maxSources else{throw Failure.tooLarge}
        var remaining=maxBytes,sources:[String]=[]
        for url in urls {let source=try readSource(url,limit:remaining);remaining-=source.utf8.count;sources.append(source)}
        return sources
    }
    static func prepare(_ sources:[String])throws->[NativeCredentialRecord] {
        guard !sources.isEmpty else{throw Failure.empty}
        guard sources.count<=maxSources else{throw Failure.tooLarge}
        var remaining=maxBytes
        var records:[NativeCredentialRecord]=[]
        var seen=Set<String>()
        func add(_ raw:String,_ expected:TransportProtocol)throws {
            guard records.count<maxSources else{throw Failure.tooLarge}
            guard seen.insert(raw).inserted else{throw Failure.duplicate}
            records.append(try NativeCredentialRecord.create(profileID:UUID(),expected:expected,source:raw))
        }
        for text in sources {
            let bytes=text.utf8.prefix(remaining+1).count
            guard bytes<=remaining else{throw Failure.tooLarge};remaining-=bytes
            let source=text.trimmingCharacters(in:.whitespacesAndNewlines)
            guard !source.isEmpty else{throw Failure.empty}
            if source.lowercased().hasPrefix("vless://") {
                for line in source.components(separatedBy:.newlines) {
                    let uri=line.trimmingCharacters(in:.whitespacesAndNewlines)
                    if uri.isEmpty {continue}
                    guard uri.lowercased().hasPrefix("vless://") else{throw Failure.unsupported}
                    try add(uri,.vlessReality)
                }
            } else {
                // Only a fully validated WG grammar may identify a protocol.
                // Unknown/partial AWG variants never fall back to pure WG.
                let preview=try WGQuickConfigurationPreview.parse(source)
                try add(source,preview.format == .wireGuard ? .wireGuard:.amneziaWG1)
            }
        }
        guard !records.isEmpty else{throw Failure.empty};return records
    }
}
