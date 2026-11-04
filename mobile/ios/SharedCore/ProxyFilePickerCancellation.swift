import Foundation

/// File-provider cancellation is not a failed proxy file or invalid backup.
/// Only suppress the well-defined Cocoa user-cancel error, not arbitrary
/// NSError with the same code from other subsystems.
enum ProxyFilePickerCancellation {
    static func isUserCancellation(_ error: Error) -> Bool {
        let ns = error as NSError
        return ns.domain == NSCocoaErrorDomain && ns.code == NSUserCancelledError
    }
}
