import SwiftUI
import UIKit

private struct ScaledEmptyStatus: UIViewRepresentable {
    var text: String
    func makeUIView(context: Context) -> UILabel {
        let view = UILabel()
        view.numberOfLines = 0
        view.adjustsFontForContentSizeCategory = true
        view.font = UIFont.preferredFont(forTextStyle: .body)
        view.textColor = .label
        return view
    }
    func updateUIView(_ view: UILabel, context: Context) {
        view.font = UIFont.preferredFont(forTextStyle: .body, compatibleWith: view.traitCollection)
        view.text = text
        view.accessibilityLabel = text
        view.invalidateIntrinsicContentSize()
    }
}

struct ExclusionsView: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [String] = []
    @State private var graph = SmartExclusionGraph()
    @State private var scannedParent = ""
    @State private var externalHints: [String] = []
    @State private var pendingExternalHost: String?
    @State private var confirmExternal = false
    @State private var undoEntries: [String]?
    @State private var undoGraph: SmartExclusionGraph?
    @Environment(\.dynamicTypeSize) private var textSize
    @FocusState private var isDomainFocused: Bool
    @State private var input = ""
    @State private var localError: String?
    @State private var confirmClearAll = false
    @State private var saving = false
    @State private var discovered: [String] = []
    @State private var selectedDiscovered: Set<String> = []
    @State private var scanning = false
    @State private var scanner: ExclusionWebScanner?

    var body: some View {
        NavigationView {
            List {
                editorSection
                if !discovered.isEmpty {
                    Section(SmartExclusionsUX.text("Найденные домены — выберите для исключения")) {
                        ForEach(discovered, id: \.self) { host in
                            Button {
                                if !selectedDiscovered.insert(host).inserted { selectedDiscovered.remove(host) }
                            } label: {
                                HStack {
                                    Text(host).foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: selectedDiscovered.contains(host) ? "checkmark.circle.fill" : "circle")
                                }
                            }
                        }
                        Button(SmartExclusionsUX.text("Подтвердить выбранные для обхода")) {
                            do {
                                snapshotUndo()
                                var next = graph
                                for child in selectedDiscovered {
                                    try next.set(.approved, parent: scannedParent, child: child)
                                }
                                let manual = try SiteExclusionPolicy.normalizeAll(entries + [scannedParent])
                                _ = try next.effective(manual: manual)
                                graph = next
                                entries = manual
                                discovered = []
                                selectedDiscovered = []
                                localError = nil
                            } catch { localError = error.localizedDescription }
                        }.disabled(selectedDiscovered.isEmpty)
                    }
                }
                if !externalHints.isEmpty {
                    Section {
                        ForEach(externalHints, id: \.self) { host in
                            HStack {
                                Text(host).textSelection(.enabled)
                                Spacer()
                                Button(SmartExclusionsUX.text("Добавить вручную")) {
                                    pendingExternalHost = host
                                    confirmExternal = true
                                }
                                .buttonStyle(.borderless)
                                .frame(minHeight: 44)
                                .accessibilityLabel(SmartExclusionsUX.text("Добавить вручную") + " " + host)
                            }
                        }
                    } header: {
                        Text(SmartExclusionsUX.text("Сторонние ресурсы — только вручную"))
                    } footer: {
                        Text(SmartExclusionsUX.text("Сторонние домены могут обслуживать рекламу или использовать общие IP-адреса. Добавление вручную направит все соединения к этим IP мимо VPN. Без явного подтверждения правила не меняются."))
                    }
                }
                if !graph.edges.isEmpty {
                    Section {
                        ForEach(Array(Set(graph.edges.map(\.parent))).sorted(), id: \.self) { parent in
                            DisclosureGroup(parent) {
                                ForEach(graph.edges.filter { $0.parent == parent }) { edge in
                                    graphEdgeRow(edge, parent: parent)
                                }
                                Button(SmartExclusionsUX.text("Удалить связи сайта"), role: .destructive) {
                                    snapshotUndo()
                                    graph.remove(parent: parent)
                                }
                            }
                        }
                    } header: {
                        Text(SmartExclusionsUX.text("Связанные домены (требуют подтверждения)"))
                    } footer: {
                        Text(SmartExclusionsUX.text("Связи хранятся локально 7 дней. Повторный анализ обновляет дату наблюдения, но не меняет ваше решение. Сторонние CDN не обходятся автоматически."))
                    }
                }
                if undoEntries != nil {
                    Section {
                        Button(SmartExclusionsUX.text("Отменить последнее изменение")) { restoreUndo() }
                    }
                }
                Section {
                    if entries.isEmpty {
                        HStack(spacing: 12) {
                            Image(systemName: "tray")
                                .accessibilityHidden(true)
                            ScaledEmptyStatus(text: AppL10n.tr("Список пока пуст"))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
                    }
                    ForEach(entries, id: \.self) { host in
                        HStack(spacing: 12) {
                            Text(host)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if host.contains(".") && !host.contains(":") {
                                Button { scanSite(host) } label: {
                                    Image(systemName: "magnifyingglass")
                                        .frame(minWidth: 44, minHeight: 44)
                                }
                                .disabled(scanning)
                                .buttonStyle(.borderless)
                                .accessibilityLabel(SmartExclusionsUX.text("Найти связанные домены для ") + host)
                            }
                            Button(role: .destructive) {
                                snapshotUndo()
                                entries.removeAll { $0 == host }
                                graph.remove(parent: host)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(AppL10n.tr("Удалить исключение") + " \(host)")
                        }
                    }
                    .onDelete { offsets in
                        snapshotUndo()
                        let removed = offsets.map { entries[$0] }
                        entries.remove(atOffsets: offsets)
                        for host in removed { graph.remove(parent: host) }
                    }
                } header: {
                    if !entries.isEmpty {
                        HStack {
                            Text(AppL10n.tr("Исключения") + " (\(entries.count))")
                                .font(.subheadline)
                            Spacer()
                            Button("Очистить все", role: .destructive) {
                                confirmClearAll = true
                            }
                            .font(.subheadline)
                            .buttonStyle(.borderless)
                            .accessibilityHint("Удалить все исключения после подтверждения")
                        }
                    }
                } footer: {
                    if !entries.isEmpty {
                        Text(SmartExclusionsUX.text("Изменения вступят в силу после сохранения и переподключения VPN."))
                    }
                }
            }
            .navigationTitle("Исключения сайтов")
            .navigationBarTitleDisplayMode(.large)
            .tint(Brand.mint)
            .confirmationDialog(
                "Очистить все исключения?",
                isPresented: $confirmClearAll,
                titleVisibility: .visible
            ) {
                Button("Очистить все", role: .destructive) {
                    snapshotUndo()
                    entries.removeAll()
                    graph = SmartExclusionGraph()
                    discovered = []
                    selectedDiscovered = []
                    externalHints = []
                    input = ""
                    localError = nil
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Все исключения будут удалены из списка. Изменения применятся только после нажатия «Сохранить».")
            }
            .confirmationDialog(SmartExclusionsUX.text("Разрешить прямой доступ для стороннего домена?"),
                                isPresented: $confirmExternal, titleVisibility: .visible) {
                Button(SmartExclusionsUX.text("Добавить вручную")) {
                    guard let host = pendingExternalHost else { return }
                    do {
                        let updated = try SiteExclusionPolicy.normalizeAll(entries + [host])
                        _ = try graph.effective(manual: updated)
                        snapshotUndo()
                        entries = updated
                        externalHints.removeAll { $0 == host }
                        localError = nil
                    } catch { localError = error.localizedDescription }
                    pendingExternalHost = nil
                }
                Button("Отмена", role: .cancel) { pendingExternalHost = nil }
            } message: {
                Text(SmartExclusionsUX.text("Общий IP-адрес может обслуживать и другие сайты. Такой обход касается всего IP, не только выбранного домена."))
            }
            .onAppear {
                entries = model.manualExclusions
                graph = model.smartGraph.pruned()
            }
            .onDisappear { cancelScan() }
            .keyboardDismissToolbar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(Brand.text)
                            .frame(width: 44, height: 44)
                            .background(Color.clear)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(AppL10n.tr("Отмена"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        guard !saving else { return }
                        cancelScan()
                        if !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { addEntry() }
                        guard localError == nil else { return }
                        saving = true
                        Task {
                            let success = await model.saveExclusions(entries, graph: graph)
                            saving = false
                            if success { dismiss() }
                        }
                    } label: {
                        Group {
                            if textSize.isAccessibilitySize {
                                Image(systemName: "checkmark")
                                    .font(.title3.weight(.bold))
                                    .frame(width: 48, height: 48)
                            } else {
                                Text(saving ? SmartExclusionsUX.text("Сохранение…") : AppL10n.tr("Сохранить"))
                                    .font(.subheadline.weight(.semibold))
                                    // Native iOS toolbar buttons compress titles. Keep
                                    // Save on ONE line instead of 'Сохранит' + 'ь'.
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .padding(.horizontal, 8)
                                    .frame(minHeight: 44)
                            }
                        }
                        .foregroundStyle(Color.black)
                        .background(Brand.mintLight, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(saving ? SmartExclusionsUX.text("Сохранение…") : AppL10n.tr("Сохранить"))
                    .disabled(saving)
                }
            }
        }
    }

    @ViewBuilder
    private var editorSection: some View {
                Section {
                    Text(SmartExclusionsUX.text("Введите домен, URL или IP и нажмите «Добавить»."))
                        .font(.body)
                        .foregroundStyle(Brand.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Group {
                        if textSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: 8) {
                                domainField
                                addDomainButton
                            }
                        } else {
                            HStack {
                                domainField
                                addDomainButton
                            }
                        }
                    }
                    Text(SmartExclusionsUX.text("Обход VPN — только для разрешённых доменов."))
                        .font(.body)
                        .foregroundStyle(Brand.text)
                        .fixedSize(horizontal: false, vertical: true)
                    DisclosureGroup {
                        Text(SmartExclusionsUX.text("В обход VPN идут только вручную добавленные домены и связанные домены, которые вы подтвердили. Обнаружение других сайтов само по себе не меняет маршруты. Изменения применятся после сохранения и переподключения."))
                            .font(.body)
                            .foregroundStyle(Brand.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(SmartExclusionsUX.text("Совместимость: для gosuslugi.ru пока сохраняется ранее проверенное исключение gu-st.ru. Автоматический поиск других сторонних ресурсов не включает обход без вашего решения."))
                            .font(.body)
                            .foregroundStyle(Brand.text)
                            .fixedSize(horizontal: false, vertical: true)
                    } label: {
                        Group {
                            if textSize.isAccessibilitySize {
                                Label(SmartExclusionsUX.text("Подробнее о правилах обхода"), systemImage: "info.circle")
                                    .labelStyle(.iconOnly)
                                    .font(.title2)
                                    .frame(minWidth: 44, minHeight: 44)
                            } else {
                                Text(SmartExclusionsUX.text("Подробнее о правилах обхода"))
                                    .font(.body)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .accessibilityLabel(SmartExclusionsUX.text("Подробнее о правилах обхода"))
                    }
                    if let localError {
                        Text(SmartExclusionsUX.text(localError)).font(.caption).foregroundStyle(.red)
                    }
                    Button {
                        guard !scanUnavailable else { return }
                        scanSite()
                    } label: {
                        Group {
                            if textSize.isAccessibilitySize {
                                Image(systemName: "magnifyingglass")
                                    .font(.title2.weight(.semibold))
                                    .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                            } else {
                                Text(SmartExclusionsUX.text(scanning ? "Идёт анализ…" : "Найти связанные домены"))
                                    .font(.body.weight(.semibold))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(minHeight: 44, alignment: .leading)
                            }
                        }
                        .foregroundStyle(scanUnavailable ? Brand.text : Brand.mint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(SmartExclusionsUX.text(scanning ? "Идёт анализ…" : "Найти связанные домены"))
                    .disabled(scanUnavailable)
                    if scanning {
                        ProgressView(SmartExclusionsUX.text("Анализ ресурсов сайта"))
                        Button(SmartExclusionsUX.text("Отменить анализ")) { cancelScan() }
                    }
                }
    }

    private var scanUnavailable: Bool {
        scanning || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var domainField: some View {
        TextField("example.com", text: $input)
            .focused($isDomainFocused)
            .font(.body)
            .frame(minHeight: 44)
            .accessibilityLabel(SmartExclusionsUX.text("Домен или IP"))
            .accessibilityHint(SmartExclusionsUX.text("Можно вставить домен, URL или IP"))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
    }

    private var addDomainButton: some View {
        Button { addEntry() } label: {
            Group {
                if textSize.isAccessibilitySize {
                    Image(systemName: "plus.circle")
                        .font(.title2)
                        .frame(minWidth: 44, minHeight: 44)
                } else {
                    Text("Добавить")
                        .font(.body.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: 44)
                }
            }
            .contentShape(Rectangle())
        }
        .accessibilityLabel(AppL10n.tr("Добавить"))
    }

    private func graphEdgeRow(_ edge: SmartDependency, parent: String) -> some View {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(edge.host).textSelection(.enabled)
                                            Spacer()
                                            Text(SmartExclusionsUX.text(edge.decision.label))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Text(SmartExclusionsUX.text(edge.evidence.description))
                                            .font(.caption2).foregroundStyle(.secondary)
                                        Text(edge.lastSeen, style: .date)
                                            .font(.caption2).foregroundStyle(.secondary)
                                        HStack {
                                            Button(SmartExclusionsUX.text(edge.decision == .approved ? "Отозвать" : "Разрешить")) {
                                                toggleGraphEdge(edge, parent: parent)
                                            }
                                            .buttonStyle(.borderless)
                                            .frame(minHeight: 44)
                                            .accessibilityLabel(SmartExclusionsUX.text(edge.decision == .approved ? "Отозвать" : "Разрешить") + " " + edge.host)
                                            Button(SmartExclusionsUX.text("Удалить"), role: .destructive) {
                                                snapshotUndo()
                                                graph.remove(parent: parent, child: edge.host)
                                            }
                                            .buttonStyle(.borderless)
                                            .frame(minHeight: 44)
                                            .accessibilityLabel(SmartExclusionsUX.text("Удалить") + " " + edge.host)
                                        }
                                    }
    }

    private func toggleGraphEdge(_ edge: SmartDependency, parent: String) {
        do {
            snapshotUndo()
            var next = graph
            let action: SmartDecision = edge.decision == .approved ? .rejected : .approved
            try next.set(action, parent: parent, child: edge.host)
            let manual: [String]
            if edge.decision == .approved {
                manual = entries
            } else {
                manual = try SiteExclusionPolicy.normalizeAll(entries + [parent])
            }
            _ = try next.effective(manual: manual)
            graph = next
            entries = manual
        } catch {
            localError = error.localizedDescription
        }
    }

    private func snapshotUndo() {
        undoEntries = entries
        undoGraph = graph
    }

    private func restoreUndo() {
        guard let saved = undoEntries, let savedGraph = undoGraph else { return }
        entries = saved
        graph = savedGraph
        undoEntries = nil
        undoGraph = nil
        localError = nil
    }

    private func cancelScan() {
        scanner?.cancel()
        scanner = nil
        scanning = false
    }

    private func scanSite() { scanSite(input) }

    private func scanSite(_ site: String) {
        do {
            guard let host = try SiteExclusionPolicy.normalize(site), !host.isEmpty else { return }
            guard SiteDependencyDiscovery.isScannableHost(host) else {
                localError = "Для поиска зависимостей укажите корректный домен сайта, а не IP-адрес"
                return
            }
            scanning = true
            discovered = []
            externalHints = []
            selectedDiscovered = []
            localError = nil
            let worker = ExclusionWebScanner()
            scanner = worker
            worker.scan(host: host) { result in
                guard scanner === worker else { return }
                scanning = false
                scanner = nil
                switch result {
                case .success(let observation):
                    do {
                        snapshotUndo()
                        try graph.observe(parent: host, html: observation.html, network: observation.network)
                        scannedParent = SmartExclusionGraph.root(host) ?? host
                        externalHints = observation.external.filter { !entries.contains($0) }
                        discovered = graph.edges.filter {
                            $0.parent == scannedParent && $0.decision == .pending && !entries.contains($0.host)
                        }.map(\.host).sorted()
                        if discovered.isEmpty { localError = "Новых связанных доменов не обнаружено" }
                    } catch { localError = error.localizedDescription }
                case .failure(let error): localError = error.localizedDescription
                }
            }
        } catch { localError = error.localizedDescription }
    }

    private func addEntry() {
        isDomainFocused = false
        do {
            if let value = try SiteExclusionPolicy.normalize(input) {
                let updated = try SiteExclusionPolicy.normalizeAll(entries + [value])
                _ = try graph.effective(manual: updated)
                if updated != entries { snapshotUndo() }
                entries = updated
            }
            input = ""
            localError = nil
        } catch {
            localError = error.localizedDescription
        }
    }
}
