import SwiftUI
import UIKit

/// Shared close control for text, secure and numeric keyboards.
/// Hiding the keyboard never submits or changes the form's contents.
struct KeyboardDismissSupport: ViewModifier {
    func body(content: Content) -> some View {
        Group {
            if #available(iOS 16.0, *) {
                content.scrollDismissesKeyboard(.interactively)
            } else {
                content
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil, from: nil, for: nil
                    )
                } label: {
                    Label(AppL10n.tr("Готово"), systemImage: "keyboard.chevron.compact.down")
                }
                .accessibilityIdentifier("keyboard.dismiss")
            }
        }
    }
}

extension View {
    func keyboardDismissToolbar() -> some View {
        modifier(KeyboardDismissSupport())
    }
}
