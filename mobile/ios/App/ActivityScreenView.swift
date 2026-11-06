import SwiftUI

/// Read-only Activity presentation. Uses the single shared AppViewModel
/// for status and events; no second journal or VPN state is persisted.
struct ActivityScreenView<Header: View>: View {
    @ObservedObject var model: AppViewModel
    let statusColor: Color
    let header: Header
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var statusLabel: some View {
        // Raw IPC errors are not useful product copy or VoiceOver output.
        Label(AppL10n.tr(model.vpn.detail.contains("IPC failed")
                       ? "Не удалось открыть VPN-сессию" : model.vpn.detail),
              systemImage: "bolt.horizontal.circle")
            .foregroundStyle(statusColor)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var refreshButton: some View {
        Button(action: { model.refreshEvents() }) {
            // The label itself must own a comfortable 48×48 hit region. A frame on
            // the outer Button only enlarges layout, not its XCUI hit area.
            Text(AppL10n.tr("Обновить"))
                .foregroundStyle(Brand.mint)
                .frame(minWidth: 48, minHeight: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("activity.refresh")
    }

    @ViewBuilder
    private var statusControls: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                statusLabel
                refreshButton.frame(maxWidth: .infinity, alignment: .trailing)
            }
        } else {
            HStack {
                statusLabel
                Spacer()
                refreshButton
            }
        }
    }

    var body: some View {
        ZStack {
            Brand.canvas.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
#if !targetEnvironment(macCatalyst)
                    header
#endif
                    Text(AppL10n.tr("Активность"))
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Brand.text)
                    statusControls
                    .padding(16)
                    .background(Brand.graphite)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    if model.events.isEmpty {
                        Text(AppL10n.tr("Событий пока нет"))
                            .foregroundStyle(Brand.softGray)
                            .padding(16)
                    } else {
                        ForEach(model.events) { event in
                            eventRow(event)
                        }
                    }
                }
                .padding(18)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear { model.refreshEvents() }
    }

    private func eventRow(_ event: TunnelEvent) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(AppL10n.tr(event.type)).font(.headline)
                Spacer()
                Text(event.timestamp, style: .time).font(.caption).foregroundStyle(Brand.softGray)
            }
            if let name = event.profileName { Text(name).font(.subheadline) }
            if let detail = event.detail { Text(detail).font(.caption).foregroundStyle(Brand.softGray) }
        }
        .foregroundStyle(Brand.text)
        .padding(14)
        .background(Brand.graphite)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

}
