// Explicitly separate QA target. Never referenced by production project.yml.
import Darwin
import Foundation
import LibXray

enum NativeLabRuntime {
    static func call(_ method: String, config: String? = nil) -> [String: Any]? {
        var request: [String:Any] = ["apiVersion":3,"method":method]
        if let config { request["payload"] = ["xrayJson":config] }
        guard let data = try? JSONSerialization.data(withJSONObject:request),
              let reply = invoke(data),
              let root = try? JSONSerialization.jsonObject(with:reply) as? [String:Any],
              root["success"] as? Bool == true else { return nil }
        return root
    }

    private static func invoke(_ request: Data) -> Data? {
        guard let text = String(data:request,encoding:.utf8), let input = strdup(text) else { return nil }
        defer { free(input) }
        guard let response = CGoInvoke(input) else { return nil }
        defer { CGoFree(response) }
        let length = strnlen(response,XrayVLESSRuntimeConfig.maxResponseBytes+1)
        guard length <= XrayVLESSRuntimeConfig.maxResponseBytes else { return nil }
        return Data(bytes:response,count:length)
    }

    static var running: Bool? {
        (call("getXrayState")?["data"] as? [String:Any])?["running"] as? Bool
    }

    static func prepare(_ candidate: VLESSRealityShareLink, port:Int) throws -> String {
        guard (call("xrayVersion")?["data"] as? [String:Any])?["version"] as? String == "26.11.9",
              running == false, let response = invoke(try candidate.conversionRequest()) else {
            throw NativeLabError.stage(1)
        }
        let bytes = try XrayVLESSRuntimeConfig.prepare(candidate:candidate,converterResponse:response,socksPort:port)
        guard let text = String(data:bytes,encoding:.utf8), call("testXray",config:text) != nil else {
            throw NativeLabError.stage(2)
        }
        return text
    }
}

enum NativeLabError: Error {
    case stage(Int)
    var safeNSError: NSError {
        let code:Int
        switch self { case .stage(let value):code=value }
        return NSError(domain:"APL.IsolatedNativeLab",code:code)
    }
}
