#if !targetEnvironment(macCatalyst)
import SwiftUI
import UIKit
import OSLog
import YandexMobileAds

/// Optional native unit below the primary banner. Native views are bound
/// through the SDK so clicks, attribution and impression tracking remain valid.
/// No proxy, VPN, profile or user identity data is added to the request.
@MainActor
final class HomeNativeAdController: NSObject, ObservableObject, NativeAdDelegate {
    enum State { case idle, loading, ready, unavailable }
    @Published private(set) var state: State = .idle
    fileprivate let adView = HomeNativeAdContentView()

    private let loader = NativeAdLoader()
    private var ad: NativeAd?
    private let statusKey = "rsya.nativeStatus.v1"
    private let logger = Logger(subsystem: "ru.arvectum.proxylauncher.ios", category: "RSYA.Native")

    func load() {
        guard state == .idle, IOSAdsConfig.isEnabled else { return }
        state = .loading
        UserDefaults.standard.set("request", forKey: statusKey)
        loader.loadAd(with: AdRequest(adUnitID: IOSAdsConfig.nativeAdUnitID)) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let native):
                do {
                    try native.bind(with: adView)
                    ad = native
                    native.delegate = self
                    state = .ready
                    UserDefaults.standard.set("loaded", forKey: statusKey)
                } catch {
                    state = .unavailable
                    let details = error as NSError
                    logger.error("RSYA native bind failed code=\(details.code) domain=\(details.domain, privacy: .public)")
                    UserDefaults.standard.set("bind_failed:\(details.code)", forKey: statusKey)
                }
            case .failure:
                state = .unavailable
                logger.error("RSYA native request failed")
                UserDefaults.standard.set("failed", forKey: statusKey)
            }
        }
    }

    func nativeAdDidClick(_ ad: NativeAd) {
        logger.info("RSYA native click")
    }

    func nativeAd(_ ad: NativeAd, didTrackImpression impressionData: ImpressionData?) {
        UserDefaults.standard.set("impression", forKey: statusKey)
        logger.info("RSYA native impression")
    }
}

/// All required interactive and attribution assets are registered as native
/// ad outlets, never imitated by independent clickable SwiftUI controls.
private final class HomeNativeRatingView: UILabel, YandexMobileAds.Rating {
    var rating: NSNumber? {
        didSet { text = rating.map { "★ \($0)" } }
    }
}

private final class HomeNativeAdContentView: YandexMobileAds.NativeAdView {
    private let title: UILabel = {
        let label = UILabel()
        label.font = .boldSystemFont(ofSize: 15)
        label.numberOfLines = 2
        return label
    }()
    private let descriptionText: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.numberOfLines = 2
        return label
    }()
    private let sponsored: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 11)
        label.text = IOSAdsConfig.localizedAdLabel
        return label
    }()
    private let warning: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 10)
        label.numberOfLines = 2
        return label
    }()
    private let feedback: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("⋯", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 20)
        return button
    }()
    private let callToAction: UIButton = {
        let button = UIButton(type: .system)
        button.titleLabel?.font = .boldSystemFont(ofSize: 13)
        return button
    }()
    private let media = YandexMobileAds.NativeMediaView()
    private let icon = UIImageView()
    private let favicon = UIImageView()
    private let domain: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabel
        label.lineBreakMode = .byTruncatingMiddle
        return label
    }()
    private let age: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 11)
        return label
    }()
    private let price = UILabel()
    private let reviewCount = UILabel()
    private let rating = HomeNativeRatingView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { fatalError("Programmatic native ad only") }

    private func setup() {
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = 12
        clipsToBounds = true
        icon.contentMode = .scaleAspectFit
        favicon.contentMode = .scaleAspectFit
        media.clipsToBounds = true
        media.layer.cornerRadius = 8

        // Yandex draws its creative inside NativeMediaView; the registered
        // disclosure and feedback outlets remain visible and accessible.
        titleLabel = title
        bodyLabel = descriptionText
        sponsoredLabel = sponsored
        warningLabel = warning
        feedbackButton = feedback
        callToActionButton = callToAction
        iconImageView = icon
        mediaView = media
        domainLabel = domain
        ageLabel = age
        faviconImageView = favicon
        priceLabel = price
        ratingView = rating
        reviewCountLabel = reviewCount

        let top = UIStackView(arrangedSubviews: [age, sponsored, UIView(), feedback])
        top.axis = .horizontal
        top.alignment = .center
        top.spacing = 4
        let identity = UIStackView(arrangedSubviews: [favicon, domain])
        identity.axis = .horizontal
        identity.spacing = 4
        let textColumn = UIStackView(arrangedSubviews: [title, descriptionText, identity, callToAction])
        textColumn.axis = .vertical
        textColumn.alignment = .leading
        textColumn.spacing = 4
        let main = UIStackView(arrangedSubviews: [media, textColumn])
        main.axis = .horizontal
        main.spacing = 10
        main.alignment = .fill
        let layout = UIStackView(arrangedSubviews: [top, main, warning])
        layout.translatesAutoresizingMaskIntoConstraints = false
        layout.axis = .vertical
        layout.spacing = 4
        addSubview(layout)
        NSLayoutConstraint.activate([
            layout.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            layout.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            layout.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            layout.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            media.widthAnchor.constraint(equalTo: main.widthAnchor, multiplier: 0.36),
            favicon.widthAnchor.constraint(equalToConstant: 14),
            favicon.heightAnchor.constraint(equalToConstant: 14),
            // Apple's recommended minimum interactive target is 44x44pt.
            feedback.widthAnchor.constraint(equalToConstant: 44),
            feedback.heightAnchor.constraint(equalToConstant: 44)
        ])
    }
}

private struct HomeNativeAdUIView: UIViewRepresentable {
    let view: HomeNativeAdContentView
    func makeUIView(context: Context) -> HomeNativeAdContentView { view }
    func updateUIView(_ uiView: HomeNativeAdContentView, context: Context) {}
}

struct NativeHomeAdView: View {
    let width: CGFloat
    let height: CGFloat
    // Owned by the app's ContentView rather than recreated per Home visit.
    // The ad preloads at startup and is retained across tab navigation.
    @ObservedObject var controller: HomeNativeAdController

    var body: some View {
        Group {
            switch controller.state {
            case .ready:
                HomeNativeAdUIView(view: controller.adView)
                    .frame(height: height)
                    .accessibilityIdentifier("home.nativeAdvertisement")
            case .unavailable:
                // A no-fill/error never obscures the VPN button. The existing
                // smaller banner unit can fill this placement instead.
                SettingsBannerView(adWidth: width, maxAdHeight: 76,
                                   placement: .secondary)
            case .idle, .loading:
                Color.clear.frame(height: height)
            }
        }
        .frame(maxWidth: .infinity)
        // Keep the second ad's footprint stable across loading, impressions
        // and no-fill fallback, independently of the VPN button state.
        .frame(height: height, alignment: .top)
        .onAppear { controller.load() } // Idempotent if preloaded already.
    }
}
#endif
