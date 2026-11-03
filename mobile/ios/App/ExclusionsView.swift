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
    @State private var expandedParents: Set<String> = []
    @State private var linkingParent: String?
    @State private var linkedHostInput = ""
    @State private var externalHints: [String] = []
    @State private var diagnosticHints: [String] = []
    @State private var diagnosticProbeStatus: [String: String] = [:]
    @State private var diagnosticProbeTask: Task<Void, Never>?

    @State private var pendingExternalHost: String?
    @State private var confirmExternal = false
    @State private var undoEntries: [String]?
    @State private var undoGraph: SmartExclusionGraph?
    @Environment(\.dynamicTypeSize) private var textSize
    @FocusState private var isDomainFocused: Bool
    @State private var input = ""
    @State private var localError: String?
    @State private var scanWarning: String?
    @State private var confirmClearAll = false
    @State private var saving = false
    @State private var discovered: [String] = []
    @State private var selectedDiscovered: Set<String> = []
    @State private var scanning = false
    @State private var scanner: ExclusionWebScanner?
    @State private var queuedScans: [String] = []
    @State private var activeScanHost: String?

    /// Include derived www aliases, known compatibility hosts and already
    /// approved observed dependencies in the visible list before saving.
    private var automaticallyIncluded: [String] {
        let effective = (try? graph.effective(manual: entries)) ?? entries
        let expanded = effective.flatMap { SiteExclusionPolicy.routingHosts(for: $0) }
        return Array(Set(expanded).subtracting(Set(entries))).sorted()
    }

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
                if !diagnosticHints.isEmpty {
                    Section {
                        ForEach(diagnosticHints.filter { !entries.contains($0) }, id: \.self) { host in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(host).textSelection(.enabled)
                                    Text(SmartExclusionsUX.text("Повторные ошибки соединения через прокси"))
                                        .font(.caption).foregroundStyle(.secondary)
                                    if let diagnosis = diagnosticProbeStatus[host] {
                                        Text(SmartExclusionsUX.text(diagnosis))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }

                                }
                                Spacer()
                                Button(SmartExclusionsUX.text("Проверить исключение")) {
                                    pendingExternalHost = host
                                    confirmExternal = true
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    } header: {
                        Text(SmartExclusionsUX.text("Проблемные сайты"))
                    } footer: {
                        Text(SmartExclusionsUX.text("APL заметила ошибки подключения, но ещё не доказала, что прямой путь безопасен. Решение об исключении принимает пользователь."))
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
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 12) {
                                Text(host)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if SmartExclusionGraph.root(host) != nil {
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
                                    queuedScans.removeAll { $0 == host }
                                    if activeScanHost == host { cancelScan() }
                                    if linkingParent == SmartExclusionGraph.root(host) { linkingParent = nil }
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.red)
                                        .frame(minWidth: 44, minHeight: 44)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel(AppL10n.tr("Удалить исключение") + " \(host)")
                            }
                            if let parent = SmartExclusionGraph.root(host) {
                                DisclosureGroup(isExpanded: Binding(
                                    get: { expandedParents.contains(parent) },
                                    set: { open in
                                        if open { expandedParents.insert(parent) }
                                        else { expandedParents.remove(parent) }
                                    }
                                )) {
                                    ForEach(graph.edges.filter { $0.parent == parent }) { edge in
                                        graphEdgeRow(edge, parent: parent)
                                    }
                                    ForEach(SiteExclusionPolicy.routingHosts(for: host).filter { alias in
                                        alias != host && !graph.edges.contains {
                                            $0.parent == parent && $0.host == alias
                                        }
                                    }, id: \.self) { alias in
                                        HStack {
                                            Text(alias).textSelection(.enabled)
                                            Spacer()
                                            Text(SmartExclusionsUX.text("Системная связь"))
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    if linkingParent == parent {
                                        HStack {
                                            TextField(SmartExclusionsUX.text("Адрес связанного домена"),
                                                      text: $linkedHostInput)
                                                .textInputAutocapitalization(.never)
                                                .autocorrectionDisabled()
                                                .accessibilityIdentifier("exclusions.linkedHost")
                                            Button(AppL10n.tr("Добавить")) { addLinkedHost(to: parent) }
                                                .buttonStyle(.borderless)
                                                .accessibilityIdentifier("exclusions.submitLinked.\(parent)")
                                        }
                                    } else {
                                        Button(SmartExclusionsUX.text("Добавить связанный домен")) {
                                            linkingParent = parent
                                            linkedHostInput = ""
                                        }
                                        .frame(minHeight: 44)
                                        .accessibilityIdentifier("exclusions.addLinked.\(parent)")
                                    }
                                } label: {
                                    let observedCount = graph.edges.filter { $0.parent == parent }.count
                                    let builtInCount = SiteExclusionPolicy.routingHosts(for: host).filter { alias in
                                        alias != host && !graph.edges.contains {
                                            $0.parent == parent && $0.host == alias
                                        }
                                    }.count
                                    Text(SmartExclusionsUX.text("Связанные домены") + " (\(observedCount + builtInCount))")
                                        .font(.subheadline)
                                }
                                .accessibilityIdentifier("exclusions.group.\(parent)")
                            }
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
            // Short, already localized in all 50 legacy catalogs. The former
            // large 'Website exclusions' heading truncated on narrow iPhones
            // (notably Amharic/French) and forced the form below the fold.
            .navigationTitle("Исключения")
            .navigationBarTitleDisplayMode(.inline)
            .tint(Brand.mint)
            .confirmationDialog(
                "Очистить все исключения?",
                isPresented: $confirmClearAll,
                titleVisibility: .visible
            ) {
                Button("Очистить все", role: .destructive) {
                    cancelScan()
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
            .confirmationDialog(
                SmartExclusionsUX.text(pendingExternalHost.map { diagnosticHints.contains($0) }
                    == true ? "Добавить проблемный сайт в обход VPN?"
                    : "Разрешить прямой доступ для стороннего домена?"),
                isPresented: $confirmExternal, titleVisibility: .visible) {
                Button(SmartExclusionsUX.text("Добавить вручную")) {
                    guard let host = pendingExternalHost else { return }
                    do {
                        let roots = entries.compactMap(SmartExclusionGraph.root)
                        let inferredParent = roots.filter { host.hasSuffix("." + $0) }
                            .sorted { $0.count > $1.count }.first
                        let linkedParent = !diagnosticHints.contains(host) && roots.contains(scannedParent)
                            ? scannedParent : inferredParent
                        if let linkedParent {
                            var next = graph
                            try next.addUserLink(parent: linkedParent, child: host)
                            _ = try next.effective(manual: entries)
                            snapshotUndo()
                            graph = next
                            expandedParents.insert(linkedParent)
                        } else {
                            let updated = try SiteExclusionPolicy.normalizeAll(entries + [host])
                            _ = try graph.effective(manual: updated)
                            snapshotUndo()
                            entries = updated
                            if SiteDependencyDiscovery.isScannableHost(host) { queueScan(host) }
                        }
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
                model.refresh()
                entries = model.manualExclusions
                graph = model.smartGraph.pruned()
                expandedParents = Set(entries.compactMap(SmartExclusionGraph.root))
                diagnosticHints = model.adaptiveRouteLearning.diagnosticCandidates()
                diagnosticProbeTask?.cancel()
                diagnosticProbeTask = Task { await checkDiagnosticHosts() }
            }
            .onDisappear {
                cancelScan()
                diagnosticProbeTask?.cancel()
                diagnosticProbeTask = nil
            }
            .keyboardDismissOnSwipeUp()
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
                        // The first tap with an unsaved hostname adds and
                        // scans it; a later Save persists completed results.
                        guard !scanning && queuedScans.isEmpty else { return }
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
                    .disabled(saving || scanning || !queuedScans.isEmpty)
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
                        Text(SmartExclusionsUX.text("В автоматическом режиме проверенные поддомены добавляются сами. В ручном режиме выбирайте их из предложений. Сохраните изменения для применения."))
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
                    if let scanWarning {
                        Text(SmartExclusionsUX.text(scanWarning))
                            .font(.caption).foregroundStyle(.secondary)
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
                                        Text(SmartExclusionsUX.text(edge.userLinked == true ? "Добавлено вручную" : edge.evidence.description))
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

    @MainActor
    private func checkDiagnosticHosts() async {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-qaSmart3FailureFixture") {
            // No live hostname or user connection under the DEBUG fixture.
            return
        }
#endif
        for host in diagnosticHints.prefix(3) {
            if Task.isCancelled { return }
            diagnosticProbeStatus[host] = "Проверяется TLS-соединение…"
            let result = await AdaptiveDirectProbe.checkTLS(host: host)
            if Task.isCancelled { return }
            switch result {
            case .tlsReadyViaWiFi:
                diagnosticProbeStatus[host] = "TLS через Wi-Fi доступен (маршрут не подтверждён)"
            case .tlsReadyViaCellular:
                diagnosticProbeStatus[host] = "TLS через мобильную сеть доступен (маршрут не подтверждён)"
            case .unavailable:
                diagnosticProbeStatus[host] = "Проверка TLS не удалась"
            }
        }
    }

    private func cancelScan() {
        scanner?.cancel()
        scanner = nil
        scanning = false
        activeScanHost = nil
        queuedScans = []
    }

    private func queueScan(_ host: String) {
        guard SiteDependencyDiscovery.isScannableHost(host) else { return }
        if scanning {
            if activeScanHost != host && !queuedScans.contains(host) { queuedScans.append(host) }
        } else { scanSite(host) }
    }

    private func scanNextQueuedSite() {
        guard !queuedScans.isEmpty else { return }
        let next = queuedScans.removeFirst()
        // Start immediately to avoid a brief Save-enabled race between
        // queued scans after adding multiple domains.
        scanSite(next)
    }

    private func scanSite() { scanSite(input) }

    private func scanSite(_ site: String) {
        do {
            guard let host = try SiteExclusionPolicy.normalize(site), !host.isEmpty else { return }
            guard SiteDependencyDiscovery.isScannableHost(host) else {
                localError = "Для поиска зависимостей укажите корректный домен сайта, а не IP-адрес"
                return
            }
            guard !scanning else { queueScan(host); return }
            scanning = true
            activeScanHost = host
            discovered = []
            externalHints = []
            selectedDiscovered = []
            localError = nil
            scanWarning = nil
            let worker = ExclusionWebScanner()
            scanner = worker
            worker.scan(host: host) { result in
                guard scanner === worker else { return }
                scanning = false
                activeScanHost = nil
                scanner = nil
                switch result {
                case .success(let observation):
                    do {
                        snapshotUndo()
                        try graph.observe(parent: host, html: observation.html, network: observation.network)
                        let autoAdded = model.automaticSiteExpansion
                            ? graph.approveStrongFirstParty(parent: host, manual: entries) : []
                        scannedParent = SmartExclusionGraph.root(host) ?? host
                        externalHints = observation.external.filter {
                            !entries.contains($0) && !automaticallyIncluded.contains($0)
                        }
                        discovered = graph.edges.filter {
                            $0.parent == scannedParent && $0.decision == .pending && !entries.contains($0.host)
                        }.map(\.host).sorted()
                        if discovered.isEmpty && externalHints.isEmpty && autoAdded.isEmpty {
                            scanWarning = "Новых связанных доменов не обнаружено"
                        }
                    } catch { scanWarning = error.localizedDescription }
                case .failure(let error): scanWarning = error.localizedDescription
                }
                scanNextQueuedSite()
            }
        } catch { localError = error.localizedDescription }
    }

    private func addLinkedHost(to parent: String) {
        do {
            guard entries.contains(where: { SmartExclusionGraph.root($0) == parent }) else {
                throw SmartGraphError.invalidParent
            }
            var next = graph
            try next.addUserLink(parent: parent, child: linkedHostInput)
            _ = try next.effective(manual: entries)
            snapshotUndo()
            graph = next
            linkingParent = nil
            linkedHostInput = ""
            localError = nil
        } catch { localError = error.localizedDescription }
    }

    private func addEntry() {
        isDomainFocused = false
        do {
            if let value = try SiteExclusionPolicy.normalize(input) {
                let updated = try SiteExclusionPolicy.normalizeAll(entries + [value])
                _ = try graph.effective(manual: updated)
                let newlyAdded = updated != entries
                if newlyAdded { snapshotUndo() }
                entries = updated
                if let parent = SmartExclusionGraph.root(value) { expandedParents.insert(parent) }
                // This is the core user flow: Add A automatically initiates
                // one bounded HTML + runtime request scan for B/C.
                if newlyAdded { queueScan(value) }
            }
            input = ""
            localError = nil
        } catch {
            localError = error.localizedDescription
        }
    }
}
