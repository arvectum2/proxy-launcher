// Pure policy used by both real NWPath adapters. No network or storage access.
import Foundation

enum NativePhysicalPathPolicy {
    // Caller passes only Wi-Fi/cellular interfaces actually used by the path.
    // An unsatisfied observation is not a physical selection.
    static func uniqueInterface(satisfied:Bool,eligibleNames:[String])->String? {
        guard satisfied else{return nil}
        let names=Set(eligibleNames)
        return names.count==1 ? names.first:nil
    }

    struct Signature:Equatable {
        let satisfied:Bool
        let interfaces:[String]
        let expensive:Bool
        let constrained:Bool
        init(satisfied:Bool,interfaces:[String],expensive:Bool,constrained:Bool){
            self.satisfied=satisfied
            self.interfaces=interfaces.sorted()
            self.expensive=expensive
            self.constrained=constrained
        }
    }

    // A changed/unsatisfied path revokes the current generation. A new
    // physical route requires a new session; it cannot revive this instance.
    struct Session {
        private(set) var baseline:Signature?
        private(set) var revoked=false
        mutating func observe(_ signature:Signature)->Bool {
            guard !revoked else{return false}
            guard signature.satisfied,baseline==nil || baseline==signature else{
                revoked=true;return false
            }
            baseline=signature;return true
        }
    }
}
