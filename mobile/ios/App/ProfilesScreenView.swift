import SwiftUI

/// Profile library UI; uses AppViewModel for all persistence, never a second
/// store, Keychain, VPN controller, or credentials cache.
struct ProfilesScreenView<Header: View>: View {
    @ObservedObject var model: AppViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var editorProfile: ProxyProfile?
    @Binding var showNewProfile: Bool
    @Binding var showProfileBackup: Bool
    let onImport: () -> Void
    let header: Header

    @State private var sharingProfile: ProxyProfile?
    @State private var profileSearch = ""
    @State private var profileGroupFilter = "all"
    @State private var pendingGroupIDs: Set<UUID> = []
    @State private var customGroupName = ""
    @State private var showNewProfileGroup = false
    @State private var profileBulkMode = false
    @State private var bulkSelectedIDs: Set<UUID> = []
    @State private var confirmBulkDelete = false

    var body: some View {
        ZStack {
            Brand.canvas.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
#if !targetEnvironment(macCatalyst)
                    header
#endif
                    profileActionButtons
                    if model.profiles.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "tray")
                                .font(.system(size: 32, weight: .light))
                                .accessibilityHidden(true)
                            Text(AppL10n.tr("Нет прокси"))
                                .font(.subheadline)
                        }
                        .foregroundStyle(Brand.softGray)
                        .frame(maxWidth: .infinity, minHeight: 150)
                        .accessibilityIdentifier("profiles.emptyState")
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            ProfileLibraryFiltersView(
                                model: model, search: $profileSearch,
                                groupFilter: $profileGroupFilter,
                                bulkMode: $profileBulkMode,
                                selectedIDs: $bulkSelectedIDs
                            )
                            ForEach(visibleProfiles) { profile in
                                ProfileLibraryRowView(
                                    model: model, profile: profile,
                                    bulkMode: profileBulkMode,
                                    isSelected: bulkSelectedIDs.contains(profile.id),
                                    onOpen: { editorProfile = profile },
                                    onShare: { sharingProfile = profile },
                                    onToggleSelection: {
                                        if !bulkSelectedIDs.insert(profile.id).inserted {
                                            bulkSelectedIDs.remove(profile.id)
                                        }
                                    },
                                    onNewGroup: newGroup
                                )
                            }
                            if visibleProfiles.isEmpty {
                                Text(AppL10n.tr("Нет профилей по выбранному фильтру"))
                                    .font(.footnote).foregroundStyle(Brand.softGray)
                            }
                            if profileBulkMode {
                                ProfileLibraryBulkActionsView(
                                    model: model, visibleProfiles: visibleProfiles,
                                    selectedVisibleIDs: selectedVisibleIDs,
                                    onSelectAll: { bulkSelectedIDs = Set(visibleProfiles.map(\.id)) },
                                    onClearSelection: { bulkSelectedIDs.removeAll() },
                                    onDelete: { confirmBulkDelete = true },
                                    onNewGroup: newGroup
                                )
                            }
                        }
                        .padding(16)
                        .background(Brand.graphite)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                }
                .padding(18)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .keyboardDismissOnSwipeUp()
        }
        .sheet(item: $sharingProfile) { profile in
            ProfileShareView(profile: profile).environmentObject(model)
        }
        .onChange(of: profileSearch) { _ in bulkSelectedIDs.removeAll() }
        .onChange(of: profileGroupFilter) { _ in bulkSelectedIDs.removeAll() }
        .onChange(of: model.profiles.map(\.id)) { liveIDs in
            bulkSelectedIDs.formIntersection(Set(liveIDs))
        }
        .alert(AppL10n.tr("Новая группа"), isPresented: $showNewProfileGroup) {
            TextField(AppL10n.tr("Название группы"), text: $customGroupName)
            Button(AppL10n.tr("Сохранить")) {
                let name = customGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { model.assignProfileGroup(name, to: pendingGroupIDs) }
                pendingGroupIDs.removeAll()
            }
            Button(AppL10n.tr("Отмена"), role: .cancel) { pendingGroupIDs.removeAll() }
        } message: {
            Text(AppL10n.tr("Группы изменяют только организацию списка, не маршрутизацию VPN."))
        }
        .confirmationDialog(AppL10n.tr("Удалить выбранные прокси?"), isPresented: $confirmBulkDelete, titleVisibility: .visible) {
            Button(AppL10n.tr("Удалить безвозвратно"), role: .destructive) {
                guard !model.vpn.isConnectedOrConnecting else { return }
                let removed = model.deleteProfiles(ids: selectedVisibleIDs)
                bulkSelectedIDs.subtract(removed)
                if bulkSelectedIDs.isEmpty { profileBulkMode = false }
            }
        } message: {
            Text(AppL10n.tr("Профили и сохранённые пароли будут удалены без возможности восстановления."))
        }
    }

    /// Hidden and stale rows never participate in destructive operations,
    /// even when they were selected before changing search/group filters.
    private var selectedVisibleIDs: Set<UUID> {
        ProfileLibrarySelectionPolicy.selectedVisibleIDs(bulkSelectedIDs, from: visibleProfiles)
    }

    private var visibleProfiles: [ProxyProfile] {
        ProfileLibrarySelectionPolicy.visibleProfiles(
            model.profiles, search: profileSearch, groupFilter: profileGroupFilter,
            organization: model.profileOrganization
        )
    }

    private func newGroup(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        pendingGroupIDs = ids
        customGroupName = ""
        showNewProfileGroup = true
    }

    /// Three compact actions on a standard iPhone. Large accessibility text
    /// gets full-width rows rather than truncating localized button titles.
    @ViewBuilder
    private var profileActionButtons: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 8) { profileActionLabels }
        } else {
            HStack(spacing: 8) { profileActionLabels }
        }
    }

    @ViewBuilder
    private var profileActionLabels: some View {
        cardButton("Добавить", filled: true) { showNewProfile = true }
        cardButton("Импорт", filled: false, action: onImport)
            .accessibilityIdentifier("profiles.import")
        cardButton("Копия", filled: false) { showProfileBackup = true }
            .accessibilityLabel(AppL10n.tr("Резервные копии"))
            .accessibilityIdentifier("profiles.encryptedBackup")
    }

    private func cardButton(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(AppL10n.tr(title), action: action)
            .font(.subheadline.weight(.bold))
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .multilineTextAlignment(.center)
            .foregroundStyle(filled ? Brand.actionText : Brand.mintLight)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 46)
            .background(filled ? Brand.mint : Brand.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Brand.mint.opacity(filled ? 0 : 0.6)))
    }

}
