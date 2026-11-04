import SwiftUI

#if targetEnvironment(macCatalyst)
/// Gives both desktop home cards the height of the taller card at the
/// available column width. Unlike a hard-coded height this also accommodates
/// longer localized copy, font scaling and window resizing.
struct EqualHeightDashboardLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = max(0, proposal.width ?? 0)
        guard !subviews.isEmpty else { return CGSize(width: width, height: 0) }
        let cardWidth = max(0, (width - spacing * CGFloat(subviews.count - 1)) / CGFloat(subviews.count))
        let tallest = subviews.map {
            $0.sizeThatFits(ProposedViewSize(width: cardWidth, height: nil)).height
        }.max() ?? 0
        return CGSize(width: width, height: tallest)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard !subviews.isEmpty else { return }
        let cardWidth = max(0, (bounds.width - spacing * CGFloat(subviews.count - 1)) / CGFloat(subviews.count))
        for (index, card) in subviews.enumerated() {
            card.place(
                at: CGPoint(x: bounds.minX + CGFloat(index) * (cardWidth + spacing), y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: cardWidth, height: bounds.height)
            )
        }
    }
}
#endif
