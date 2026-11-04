import SwiftUI

/// Profile search, group/favorites filter and bounded manual health scan.
/// Keyboard focus is local to this component; swipe-up dismissal remains on
/// the containing ProfilesScreenView scroll surface.
struct ProfileLibraryFiltersView: View {
    @ObservedObject var model: AppViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var search: String
    @Binding var groupFilter: String
    @Binding var bulkMode: Bool
    @Binding var selectedIDs: Set<UUID>
    @FocusState private var searchFocused: Bool

    private var profileLibraryTitle: some View {
        Text(AppL10n.tr("Профили"))
            .font(.headline)
            .foregroundStyle(Brand.text)
    }

    private var selectModeButton: some View {
        Button(bulkMode ? AppL10n.tr("Готово") : AppL10n.tr("Выбрать")) {
            bulkMode.toggle()
            selectedIDs.removeAll()
            searchFocused = false
        }
        .foregroundStyle(Brand.mint)
        .frame(minHeight: 44)
        .accessibilityIdentifier("profiles.bulk.toggle")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    profileLibraryTitle
                    selectModeButton.frame(maxWidth: .infinity, alignment: .trailing)
                }
            } else {
                HStack {
                    profileLibraryTitle
                    Spacer()
                    selectModeButton
                }
            }
            HStack {
                Button {
                    Task { await model.scanProfiles(manual: true) }
                } label: {
                    Label(model.isScanningProfiles ? AppL10n.tr("Проверка…") :
                          AppL10n.tr("Проверить"), systemImage: "waveform.path.ecg")
                }
                .disabled(model.isScanningProfiles)
                .accessibilityHint(AppL10n.tr("Проверить следующие 10 прокси"))
                .frame(minHeight: 44)
                Spacer()
                if model.isScanningProfiles { ProgressView() }
            }
            if !model.lastProfileScanSummary.isEmpty {
                Text(model.lastProfileScanSummary)
                    .font(.caption).foregroundStyle(Brand.softGray)
            }
            TextField(AppL10n.tr("Поиск по названию или адресу"), text: $search)
                .focused($searchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit { searchFocused = false }
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("profiles.search")
            Menu {
                Button(AppL10n.tr("Все профили")) { groupFilter = "all" }
                Button(AppL10n.tr("Избранные")) { groupFilter = "favorites" }
                ForEach(model.profileOrganization.groupNames, id: \.self) { group in
                    Button(AppL10n.tr(group)) { groupFilter = "group:" + group }
                }
            } label: {
                Label(groupFilter == "all" ? AppL10n.tr("Все профили") :
                      groupFilter == "favorites" ? AppL10n.tr("Избранные") :
                      AppL10n.tr(String(groupFilter.dropFirst(6))),
                      systemImage: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(Brand.mintLight)
                    .frame(minHeight: 44)
            }
            .accessibilityIdentifier("profiles.groupFilter")
        }
    }
}
