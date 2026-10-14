import SwiftUI

/// A locally bundled, manually approved sponsorship creative.
///
/// No ad network, analytics SDK, identifier, VPN data or background request
/// is used. The browser opens only when the user explicitly taps the sponsor.
struct SponsoredPlacement: Decodable {
    let enabled: Bool
    let advertiser: String
    let headline: String
    let summary: String
    let destination: String

    static let current: SponsoredPlacement? = {
        guard let file = Bundle.main.url(forResource: "SponsoredPlacement", withExtension: "json"),
              let data = try? Data(contentsOf: file),
              let offer = try? JSONDecoder().decode(SponsoredPlacement.self, from: data),
              offer.enabled,
              !offer.advertiser.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !offer.headline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !offer.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let destination = URLComponents(string: offer.destination),
              destination.scheme == "https",
              destination.host != nil,
              destination.user == nil,
              destination.password == nil,
              destination.query == nil,
              destination.fragment == nil
        else { return nil }
        return offer
    }()
}

struct SponsoredPlacementView: View {
    let placement: SponsoredPlacement

    private var destination: URL {
        // The Sponsor model is validated before it is presented.
        URL(string: placement.destination)!
    }

    private let feedbackURL = URL(string:
        "mailto:support@arvectum.com?subject=APL%20sponsorship%20feedback")!

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "megaphone")
                    .accessibilityHidden(true)
                Text("Реклама")
                    .font(.caption.weight(.bold))
                Spacer()
                Text(placement.advertiser)
                    .font(.caption)
                    .lineLimit(1)
            }
            .foregroundStyle(Color(red: 120/255, green: 250/255, blue: 230/255))

            Text(placement.headline)
                .font(.headline)
                .foregroundStyle(.white)

            Text(placement.summary)
                .font(.subheadline)
                .foregroundStyle(Color(red: 200/255, green: 210/255, blue: 220/255))
                .fixedSize(horizontal: false, vertical: true)

            Link(destination: destination) {
                Label("Открыть сайт рекламодателя", systemImage: "arrow.up.right")
                    .font(.subheadline.weight(.semibold))
            }
            .accessibilityHint("Откроет сайт рекламодателя в браузере")
            .foregroundStyle(Color(red: 120/255, green: 250/255, blue: 230/255))

            Link("Пожаловаться на рекламу", destination: feedbackURL)
                .font(.caption)
                .foregroundStyle(Color(red: 200/255, green: 210/255, blue: 220/255))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 16/255, green: 40/255, blue: 70/255))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .contain)
    }
}
