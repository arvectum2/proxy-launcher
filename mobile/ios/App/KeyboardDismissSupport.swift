import SwiftUI
import UIKit

/// An upward swipe in the editable content hides any active iOS keyboard,
/// including numberPad, secure fields and TextEditor. A simultaneous gesture
/// preserves native scrolling, text selection and the system Home gesture.
struct KeyboardDismissSupport: ViewModifier {
    func body(content: Content) -> some View {
        Group {
            if #available(iOS 16.0, *) {
                content.scrollDismissesKeyboard(.immediately)
            } else {
                content
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 25)
                .onEnded { value in
                    // A horizontal swipe must not unexpectedly blur input.
                    guard value.translation.height < -35,
                          abs(value.translation.height) > abs(value.translation.width) * 1.2 else {
                        return
                    }
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil, from: nil, for: nil
                    )
                }
        )
    }
}

extension View {
    func keyboardDismissOnSwipeUp() -> some View {
        modifier(KeyboardDismissSupport())
    }
}
