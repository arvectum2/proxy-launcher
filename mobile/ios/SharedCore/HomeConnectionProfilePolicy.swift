// Presentation only. Never grants native connection authority.
enum HomeConnectionProfilePolicy {
    static func hasTarget(legacyCount:Int,nativeSelectionPresent:Bool,preview:Bool=false)->Bool {
        legacyCount>0 || nativeSelectionPresent || preview
    }
    static func offersAdd(legacyCount:Int,nativeSelectionPresent:Bool,preview:Bool=false,active:Bool)->Bool {
        !active && !hasTarget(legacyCount:legacyCount,nativeSelectionPresent:nativeSelectionPresent,preview:preview)
    }
}
