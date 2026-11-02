#if targetEnvironment(macCatalyst)
import SwiftUI

/// The mobile-shell view is typechecked for Mac Catalyst, but the macOS
/// product uses desktopShell and does not integrate the iOS-only ad SDK.
/// Keep a compile-time placeholder rather than linking YandexMobileAds into
/// an unrelated macOS release.
struct SettingsBannerView: View {
    var body: some View { EmptyView() }
}
#endif
