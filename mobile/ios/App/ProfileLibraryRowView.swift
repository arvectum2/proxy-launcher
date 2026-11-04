import SwiftUI

/// Render-only profile row with explicit editing and selection actions.
struct ProfileLibraryRowView: View {
    @ObservedObject var model: AppViewModel
    let profile: ProxyProfile
    let bulkMode: Bool
    let isSelected: Bool
    let onOpen: () -> Void
    let onShare: () -> Void
    let onToggleSelection: () -> Void
    let onNewGroup: (Set<UUID>) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button {
                if bulkMode { onToggleSelection() }
                else { onOpen() }
            } label: {
                HStack(spacing: 10) {
                    if bulkMode {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(Brand.mint)
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Text(profile.name)
                                .font(.subheadline.weight(.semibold))
                            if !model.automaticSelection && model.selectedProfileID == profile.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(Brand.mintLight)
                                    .accessibilityLabel(AppL10n.tr("Текущий профиль"))
                            }
                        }
                        Text("\(profile.host):\(String(profile.port)) · \(profile.type.rawValue)")
                            .font(.caption).foregroundStyle(Brand.softGray)
                            .environment(\.layoutDirection, .leftToRight)
                        if let group = model.profileOrganization.group(for: profile.id) {
                            Text(AppL10n.tr(group)).font(.caption2).foregroundStyle(Brand.mintLight)
                        }
                        if let state = model.health[profile.id] {
                            Label(state.label, systemImage: "waveform.path.ecg")
                                .font(.caption2)
                                .foregroundStyle(Brand.softGray)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Brand.text)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profiles.row.\(profile.id.uuidString)")
            .accessibilityAddTraits(bulkMode && isSelected ? .isSelected : [])
            if !bulkMode {
                Button(action: onShare) {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(Brand.mintLight)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ProfileShareUX.text("Поделиться"))
                .accessibilityIdentifier("profiles.share.\(profile.id.uuidString)")
                Button { model.toggleFavorite(profile.id) } label: {
                    Image(systemName: model.profileOrganization.isFavorite(profile.id) ? "star.fill" : "star")
                        .foregroundStyle(Brand.mint)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel(model.profileOrganization.isFavorite(profile.id) ?
                                    AppL10n.tr("Убрать из избранного") : AppL10n.tr("В избранное"))
                .accessibilityIdentifier("profiles.favorite.\(profile.id.uuidString)")
                ProfileLibraryGroupMenu(model: model, ids: [profile.id], onNewGroup: onNewGroup)
            }
        }
        .padding(.vertical, 4)
    }
}

/// One consistent group selector for a single row or a bulk selection.
struct ProfileLibraryGroupMenu: View {
    @ObservedObject var model: AppViewModel
    let ids: Set<UUID>
    let onNewGroup: (Set<UUID>) -> Void

    var body: some View {
        Menu {
            Button(AppL10n.tr("Без группы")) { model.assignProfileGroup(nil, to: ids) }
            ForEach(Array(Set(["Основные", "Рабочие", "Резервные"] +
                              model.profileOrganization.groupNames)).sorted(), id: \.self) { group in
                Button(AppL10n.tr(group)) { model.assignProfileGroup(group, to: ids) }
            }
            Button(AppL10n.tr("Новая группа…")) { onNewGroup(ids) }
        } label: {
            Label(AppL10n.tr("Группа"), systemImage: "folder.badge.plus")
                .foregroundStyle(Brand.mintLight)
                .frame(minHeight: 44)
        }
        .accessibilityLabel(AppL10n.tr("Группа профиля"))
        .disabled(ids.isEmpty)
    }
}
