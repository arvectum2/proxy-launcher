import Foundation
import Security

enum ProfileStoreError: LocalizedError {
    case noSharedDefaults
    case encodeFailed
    case corruptProfiles
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .noSharedDefaults: return "Не удалось открыть общее хранилище приложения"
        case .encodeFailed: return "Не удалось сохранить профиль"
        case .corruptProfiles: return "Хранилище профилей повреждено. Данные сохранены; изменение отменено."
        case .keychain(let status): return "Keychain error: \(status)"
        }
    }
}

enum IOSAppRoutingMode: String, CaseIterable, Identifiable {
    case normallyOn
    case normallyOff

    var id: String { rawValue }

    var title: String {
        switch self {
        case .normallyOn: return "APL обычно включён"
        case .normallyOff: return "APL обычно выключен"
        }
    }
}

final class ProfileStore {
    private enum Key {
        static let profiles = "profiles.v1"
        static let organization = "profile_organization.v1"
        static let quality = "profile_quality.v1"
        static let selectedProfileID = "selected_profile_id"
        static let automaticSelection = "automatic_selection"
        static let primaryProfileID = "primary_profile_id"
        static let restorePolicy = "restore_policy"
        static let exclusions = "site_exclusions"
        static let manualExclusions = "manual_site_exclusions.v2"
        static let smartGraph = "smart_dependency_graph.v1"
        static let automaticSiteExpansion = "automatic_site_expansion.v1"
        static let adaptiveLearning = "smart_route_evidence.v1"
        static let lastAutoProfileID = "last_auto_profile_id"
        static let recentlyFailedProfileID = "recently_failed_profile_id"
        static let recentlyFailedAt = "recently_failed_at"
        static let lastFailoverAt = "last_failover_at"
#if APL_NATIVE_PRODUCT_RUNTIME
        static let nativeProductSelection = "native_product_selection.v1"
        static let nativeProductOwner = "native_product_owner.v1"
#endif
        static let iosAppRoutingMode = "ios_app_routing_mode"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() throws {
        guard let defaults = UserDefaults(suiteName: AppShared.defaultsSuite) else {
            throw ProfileStoreError.noSharedDefaults
        }
        self.defaults = defaults
    }

    func listProfiles() -> [ProxyProfile] {
        guard let data = defaults.data(forKey: Key.profiles),
              let profiles = try? decoder.decode([ProxyProfile].self, from: data) else { return [] }
        return profiles.sorted {
            let lhs = $0.name.localizedCaseInsensitiveCompare($1.name)
            return lhs == .orderedSame ? $0.id.uuidString < $1.id.uuidString : lhs == .orderedAscending
        }
    }

    var profileOrganization: ProfileOrganization {
        get {
            guard let data = defaults.data(forKey: Key.organization),
                  var value = try? decoder.decode(ProfileOrganization.self, from: data) else {
                return ProfileOrganization()
            }
            value.prune(keeping: Set(listProfiles().map(\.id)))
            return value
        }
        set {
            var value = newValue
            value.prune(keeping: Set(listProfiles().map(\.id)))
            if let data = try? encoder.encode(value) {
                defaults.set(data, forKey: Key.organization)
            }
        }
    }

    var proxyQuality: ProxyQualitySnapshot {
        get {
            guard let data = defaults.data(forKey: Key.quality),
                  var value = try? decoder.decode(ProxyQualitySnapshot.self, from: data) else {
                return ProxyQualitySnapshot()
            }
            value.prune(keeping: Set(listProfiles().map(\.id)))
            return value
        }
        set {
            var value = newValue
            value.prune(keeping: Set(listProfiles().map(\.id)))
            if let data = try? encoder.encode(value) {
                defaults.set(data, forKey: Key.quality)
            }
        }
    }

    func profile(id: UUID) -> ProxyProfile? {
        listProfiles().first { $0.id == id }
    }

    func password(for id: UUID) throws -> String? {
        var query = baseKeychainQuery(id: id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw ProfileStoreError.keychain(status)
        }
        return String(data: data, encoding: .utf8)
    }

    /// A damaged on-disk list must never look like an empty installation to
    /// a writer. Otherwise saving one new profile would erase all old metadata.
    private func profilesForMutation() throws -> [ProxyProfile] {
        guard let raw = defaults.object(forKey: Key.profiles) else { return [] }
        guard let bytes = raw as? Data else {throw ProfileStoreError.corruptProfiles}
        guard let entries = try? decoder.decode([ProxyProfile].self, from: bytes) else {
            throw ProfileStoreError.corruptProfiles
        }
        return entries
    }

    /// Offline native preparation only; reuse the strict legacy read rather
    /// than the display list which intentionally hides corrupted storage.
    /// Separate selection, no UserDefaults or Keychain mutations.
    @MainActor func makeNativeProfilePreparation() -> NativeProfilePreparation {
        NativeProfilePreparation(legacyIDs: { [self] in Set(try profilesForMutation().map(\.id)) })
    }

    /// Inactive new-format catalog, separate from profiles.v1.
    @MainActor func makeNativeCredentialCatalog() -> NativeCredentialCatalog {
        NativeCredentialCatalog(storage:NativeCredentialCatalogKeychain(),
            repository:NativeCredentialRepository(items:NativeCredentialKeychain(purpose:.revision)),
            legacyIDs:{ [self] in Set(try profilesForMutation().map(\.id)) })
    }

    #if (DEBUG || APL_NATIVE_PRODUCT_RUNTIME) && APL_NATIVE_PROVIDER_INTEGRATION
    /// Strict read-only legacy ID check plus exact native ticket consumption.
    /// Compiles only in explicit integration Debug builds, never default Release.
    // Unknown/corrupt policy is not an empty policy. This validation path
    // cannot implement exclusions or a normally-off routing policy.
    func nativeRoutingAdmission() -> NativeRoutingAdmission {
        NativeRoutingAdmission.inspect(manual:defaults.object(forKey:Key.manualExclusions),legacy:defaults.object(forKey:Key.exclusions),graph:defaults.object(forKey:Key.smartGraph),mode:defaults.object(forKey:Key.iosAppRoutingMode))
    }
    #if APL_NATIVE_DOMAIN_POLICY_REVIEW
    func nativeDomainPolicyReview() throws -> NativeDomainPolicyReview {
        try NativeDomainPolicyReview.inspect(manual:defaults.object(forKey:Key.manualExclusions),legacy:defaults.object(forKey:Key.exclusions),graph:defaults.object(forKey:Key.smartGraph),mode:defaults.object(forKey:Key.iosAppRoutingMode))
    }
    #endif
    func nativeValidationPolicyIsEmpty() throws -> Bool {nativeRoutingAdmission().permitsSelection}

#if APL_NATIVE_RUNTIME_QA_HARNESS
    /// Disposable fixture namespace only. No migration, repair, or writes.
    func nativeRuntimeQAFixtureReference()throws->NativeCredentialRecord.Reference {
        let snapshot=try NativeCredentialCatalogReader(storage:NativeCredentialCatalogKeychain()).snapshot()
        guard let reference=snapshot.selected,try nativeRuntimeQAFixtureIsIsolated(reference) else{throw NativeCredentialCatalogReader.Failure.invalidCatalog}
        return reference
    }
    func nativeRuntimeQAFixtureIsIsolated(_ reference:NativeCredentialRecord.Reference?)throws->Bool {
        guard try profilesForMutation().isEmpty,nativeRoutingAdmission().permitsSelection else{return false}
        let reader=NativeCredentialCatalogReader(storage:NativeCredentialCatalogKeychain())
        let snapshot=try reader.snapshot()
        guard snapshot.version==2,!snapshot.hasPendingWrite,snapshot.retired.isEmpty else{return false}
        guard let reference else{return snapshot.current.count<=1}
        guard snapshot.current==[reference],snapshot.selected==reference,let nonce=try reader.selectionAuthority(reference),
              try NativeCredentialRepository(items:NativeCredentialKeychain(purpose:.revision)).read(reference) != nil else{return false}
        return try reader.snapshot()==snapshot && reader.selectionAuthority(reference)==nonce && profilesForMutation().isEmpty
    }
#endif

    @MainActor func makeNativeValidationLaunchBoundary() -> NativeSessionLaunchBoundary {
        NativeSessionLaunchBoundary(reader:NativeCredentialCatalogReader(storage:NativeCredentialCatalogKeychain()),
            repository:NativeCredentialRepository(items:NativeCredentialKeychain(purpose:.revision)),
            ticketItems:NativeCredentialKeychain(purpose:.handoff),legacyIDs:{[self] in Set(try profilesForMutation().map(\.id))},routingAdmission:{[self] in nativeRoutingAdmission()})
    }

#if APL_NATIVE_PRODUCT_RUNTIME
    func nativeProductSelection()throws->NativeProductSelection? {
        guard let raw=defaults.object(forKey:Key.nativeProductSelection) else{return nil}
        guard let bytes=raw as? Data else{throw ProfileStoreError.corruptProfiles}
        return try NativeProductSelection.read(bytes)
    }
    func selectNativeProduct(_ ref:NativeCredentialRecord.Reference)throws {
        let reader=NativeCredentialCatalogReader(storage:NativeCredentialCatalogKeychain())
        let selected=try NativeProductSelection.select(ref,catalog:reader,
            legacyIDs:Set(try profilesForMutation().map(\.id)),admission:nativeRoutingAdmission())
        defaults.set(try TransportNativeCodec.encode(selected),forKey:Key.nativeProductSelection)
    }
    func clearNativeProductSelection(){defaults.removeObject(forKey:Key.nativeProductSelection)}
    func nativeProductOwner()throws->UUID? {
        guard let raw=defaults.object(forKey:Key.nativeProductOwner) else{return nil}
        guard let text=raw as? String,let id=UUID(uuidString:text),id.uuidString==text else{throw ProfileStoreError.corruptProfiles}
        return id
    }
    func ensureNativeProductOwner()throws->UUID {
        if let owner=try nativeProductOwner(){return owner}
        let owner=UUID()
        defaults.set(owner.uuidString,forKey:Key.nativeProductOwner)
        return owner
    }
    struct ProductLaunch:CustomStringConvertible,CustomReflectable {
        let ticket:NativeCredentialHandoff.Ticket
        let options:[String:NSObject]
        var description:String {"ProductLaunch(redacted)"}
        var customMirror:Mirror {Mirror(self,children:[:])}
    }
    func issueNativeProductLaunch(_ selection:NativeProductSelection,owner:UUID)throws->ProductLaunch {
        let reader=NativeCredentialCatalogReader(storage:NativeCredentialCatalogKeychain())
        let snapshot=try reader.snapshot(),ids=Set(try profilesForMutation().map(\.id))
        let binding=NativeCredentialHandoff.Binding(reference:selection.reference,
            session:.init(epoch:UUID(),generation:1,provider:selection.reference.kind.providerName),selectionNonce:selection.nonce)
        guard try nativeProductOwner()==owner,try nativeProductSelection()==selection,
              try selection.authorizes(binding,catalog:reader,legacyIDs:ids,admission:nativeRoutingAdmission()) else{throw NativeCredentialReceiver.Failure.invalidIdentity}
        let repo=NativeCredentialRepository(items:NativeCredentialKeychain(purpose:.revision))
        guard let record=try repo.read(selection.reference) else{throw NativeCredentialReceiver.Failure.invalidIdentity}
        _=try record.compileFullTunnelCandidate(admission:nativeRoutingAdmission(),exactDNSAvailable:true)
        let handoff=makeNativeProviderValidationHandoff()
        guard try handoff.authorizes(binding),try reader.snapshot()==snapshot,try Set(profilesForMutation().map(\.id))==ids else{throw NativeCredentialReceiver.Failure.inactiveRevision}
        let ticket=try handoff.issueProductStart(record,binding:binding,owner:owner)
        do {
            guard try handoff.authorizes(binding),try reader.snapshot()==snapshot,try Set(profilesForMutation().map(\.id))==ids else{throw NativeCredentialReceiver.Failure.inactiveRevision}
            return .init(ticket:ticket,options:try NativeProductStartRequest.options(ticket:ticket,owner:owner))
        }catch{_=try handoff.revoke(ticket);throw error}
    }
    func revokeNativeProductLaunch(_ launch:ProductLaunch)throws{_=try makeNativeProviderValidationHandoff().revoke(launch.ticket)}
#endif

    func makeNativeProviderValidationHandoff() -> NativeCredentialHandoff {
        let reader=NativeCredentialCatalogReader(storage:NativeCredentialCatalogKeychain())
        return NativeCredentialHandoff(items:NativeCredentialKeychain(purpose:.handoff),
            repository:NativeCredentialRepository(items:NativeCredentialKeychain(purpose:.revision)),
            authorizes:{ [self] binding in
#if APL_NATIVE_PRODUCT_RUNTIME
                guard let selection=try nativeProductSelection() else{return false}
                return try selection.authorizes(binding,catalog:reader,
                    legacyIDs:Set(try profilesForMutation().map(\.id)),admission:nativeRoutingAdmission())
#else
                guard !(try profilesForMutation()).contains(where:{$0.id==binding.reference.profileID}) else{return false}
                return try reader.authorizes(binding)
#endif
            })
    }
    #endif

    func save(_ profile: ProxyProfile, password: String?, makeActive: Bool = true, preservePasswordIfNil: Bool = false) throws {
        var profiles = try profilesForMutation()
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) { profiles[index] = profile }
        else { profiles.append(profile) }
        guard let data = try? encoder.encode(profiles) else { throw ProfileStoreError.encodeFailed }
        // Persist the Keychain secret first. A permission or storage failure
        // must not leave a new/edited profile pointing to missing credentials.
        if !(preservePasswordIfNil && password == nil) { try setPassword(password, for: profile.id) }
        defaults.set(data, forKey: Key.profiles)
        if makeActive {
#if APL_NATIVE_PRODUCT_RUNTIME
            clearNativeProductSelection()
#endif
            defaults.set(profile.id.uuidString, forKey: Key.selectedProfileID)
            defaults.set(false, forKey: Key.automaticSelection)
        }
        if primaryProfileID == nil { primaryProfileID = profile.id }
    }

    func delete(id: UUID) throws {
        let remaining = try profilesForMutation().filter { $0.id != id }
        guard let data = try? encoder.encode(remaining) else { throw ProfileStoreError.encodeFailed }
        // Validate and delete the Keychain entry before committing the profile
        // removal. A Keychain failure must not strand saved proxy metadata.
        let keychainStatus = SecItemDelete(baseKeychainQuery(id: id) as CFDictionary)
        guard keychainStatus == errSecSuccess || keychainStatus == errSecItemNotFound else {
            throw ProfileStoreError.keychain(keychainStatus)
        }
        defaults.set(data, forKey: Key.profiles)
        if selectedProfileID == id { selectedProfileID = remaining.first?.id }
        if primaryProfileID == id { primaryProfileID = remaining.first?.id }
        if lastAutoProfileID == id { lastAutoProfileID = nil }
        if recentlyFailedProfileID == id { clearRecentlyFailed() }
        var organization = profileOrganization
        organization.prune(keeping: Set(remaining.map(\.id)))
        profileOrganization = organization
        var quality = proxyQuality
        quality.prune(keeping: Set(remaining.map(\.id)))
        proxyQuality = quality
    }

    var selectedProfileID: UUID? {
        get { uuid(forKey: Key.selectedProfileID) }
        set { setUUID(newValue, forKey: Key.selectedProfileID) }
    }

    var automaticSelection: Bool {
        get { defaults.bool(forKey: Key.automaticSelection) }
        set { defaults.set(newValue, forKey: Key.automaticSelection) }
    }

    var primaryProfileID: UUID? {
        get { uuid(forKey: Key.primaryProfileID) ?? listProfiles().first?.id }
        set { setUUID(newValue, forKey: Key.primaryProfileID) }
    }

    var restorePolicy: PrimaryRestorePolicy {
        get { PrimaryRestorePolicy(rawValue: defaults.string(forKey: Key.restorePolicy) ?? "") ?? .stayOnCurrent }
        set { defaults.set(newValue.rawValue, forKey: Key.restorePolicy) }
    }

    /// Legacy exclusions are migrated as manual rules. Rules generated by a
    /// scan always require explicit user approval and expire after seven days.
    var manualSiteExclusions: [String] {
        defaults.stringArray(forKey: Key.manualExclusions)
            ?? defaults.stringArray(forKey: Key.exclusions) ?? []
    }

    /// Preference defaults to automatic mode on fresh installs and upgrades.
    /// Switching off affects future scans, not previous manual decisions.
    var automaticSiteExpansion: Bool {
        get { (defaults.object(forKey: Key.automaticSiteExpansion) as? Bool) ?? true }
        set { defaults.set(newValue, forKey: Key.automaticSiteExpansion) }
    }

    var smartGraph: SmartExclusionGraph {
        guard let data = defaults.data(forKey: Key.smartGraph),
              let graph = try? decoder.decode(SmartExclusionGraph.self, from: data) else {
            return SmartExclusionGraph()
        }
        return graph.pruned()
    }

    /// Diagnostics are local App Group data. No automatic IP or VPN route is
    /// created from these observations on iOS; exact-host direct transport is
    /// unsupported until a separately validated platform mechanism exists.
    var adaptiveRouteLearning: AdaptiveRouteLearning {
        get {
            guard let data = defaults.data(forKey: Key.adaptiveLearning),
                  data.count <= 65_536,
                  let model = try? decoder.decode(AdaptiveRouteLearning.self, from: data),
                  model.hosts.count <= AdaptiveRouteLearning.maxHosts,
                  model.rejected.count <= 128 else { return AdaptiveRouteLearning() }
            return model
        }
        set {
            guard newValue.hosts.count <= AdaptiveRouteLearning.maxHosts,
                  newValue.rejected.count <= 128,
                  let data = try? encoder.encode(newValue),
                  data.count <= 65_536 else { return }
            defaults.set(data, forKey: Key.adaptiveLearning)
        }
    }

#if DEBUG
    /// Delete only synthetic QA host evidence after a physical test. Never
    /// clear a user's observations, exclusions, credentials or profile.
    @discardableResult
    func clearSyntheticSmart3QAEvidence() -> Bool {
        let state = adaptiveRouteLearning
        guard !state.hosts.isEmpty,
              state.rejected.isEmpty,
              state.hosts.keys.allSatisfy({ $0.hasSuffix(".qa-example.test") }) else {
            return false
        }
        defaults.removeObject(forKey: Key.adaptiveLearning)
        return true
    }
#endif

    var siteExclusions: [String] {
        get {
            // Fail closed on corrupt graph, expired evidence and overload.
            (try? smartGraph.effective(manual: manualSiteExclusions)) ?? manualSiteExclusions
        }
        set {
            // Backward compatibility for legacy callers: explicit entries
            // replace prior discovered approvals, without hidden bypasses.
            defaults.set(newValue, forKey: Key.exclusions)
            defaults.set(newValue, forKey: Key.manualExclusions)
            defaults.removeObject(forKey: Key.smartGraph)
        }
    }

    func saveSmartExclusions(manual: [String], graph: SmartExclusionGraph) throws {
        let normalized = try SiteExclusionPolicy.normalizeAll(manual)
        let current = graph.pruned()
        let effective = try current.effective(manual: normalized)
        let data = try encoder.encode(current)
        // All validation/encoding happens before the first persistent write.
        defaults.set(data, forKey: Key.smartGraph)
        defaults.set(normalized, forKey: Key.manualExclusions)
        defaults.set(effective, forKey: Key.exclusions)
    }

    var iosAppRoutingMode: IOSAppRoutingMode {
        get { IOSAppRoutingMode(rawValue: defaults.string(forKey: Key.iosAppRoutingMode) ?? "") ?? .normallyOn }
        set { defaults.set(newValue.rawValue, forKey: Key.iosAppRoutingMode) }
    }

    var lastAutoProfileID: UUID? {
        get { uuid(forKey: Key.lastAutoProfileID) }
        set { setUUID(newValue, forKey: Key.lastAutoProfileID) }
    }

    var recentlyFailedProfileID: UUID? {
        get { uuid(forKey: Key.recentlyFailedProfileID) }
        set { setUUID(newValue, forKey: Key.recentlyFailedProfileID) }
    }

    var recentlyFailedAt: Date? {
        get { defaults.object(forKey: Key.recentlyFailedAt) as? Date }
        set { defaults.set(newValue, forKey: Key.recentlyFailedAt) }
    }

    var lastFailoverAt: Date? {
        get { defaults.object(forKey: Key.lastFailoverAt) as? Date }
        set { defaults.set(newValue, forKey: Key.lastFailoverAt) }
    }

    func configuration() -> TunnelConfiguration {
        TunnelConfiguration(
            selectedProfileID: selectedProfileID,
            automaticSelection: automaticSelection,
            primaryProfileID: primaryProfileID,
            restorePolicy: restorePolicy,
            siteExclusions: siteExclusions,
            lastAutoProfileID: lastAutoProfileID,
            recentlyFailedProfileID: recentlyFailedProfileID,
            recentlyFailedAt: recentlyFailedAt,
            lastFailoverAt: lastFailoverAt
        )
    }

    func markRecentlyFailed(_ id: UUID, at: Date = Date()) {
        recentlyFailedProfileID = id
        recentlyFailedAt = at
    }

    func clearRecentlyFailed() {
        recentlyFailedProfileID = nil
        recentlyFailedAt = nil
    }

    private func setPassword(_ password: String?, for id: UUID) throws {
        let query = baseKeychainQuery(id: id)
        guard let password, !password.isEmpty else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw ProfileStoreError.keychain(status)
            }
            return
        }

        let value = Data(password.utf8)
        // Updating in place preserves the previously valid secret if the
        // replacement fails, unlike delete-then-add (which loses it).
        let updates: [String: Any] = [kSecValueData as String: value]
        let updateStatus = SecItemUpdate(query as CFDictionary, updates as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw ProfileStoreError.keychain(updateStatus)
        }
        var add = query
        add[kSecValueData as String] = value
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw ProfileStoreError.keychain(status) }
    }

    private func baseKeychainQuery(id: UUID) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AppShared.keychainService,
            kSecAttrAccount as String: id.uuidString,
        ]
        if let group = AppShared.keychainAccessGroup, !group.isEmpty {
            query[kSecAttrAccessGroup as String] = group
        }
        return query
    }

    private func uuid(forKey key: String) -> UUID? {
        defaults.string(forKey: key).flatMap(UUID.init(uuidString:))
    }

    private func setUUID(_ value: UUID?, forKey key: String) {
        if let value { defaults.set(value.uuidString, forKey: key) }
        else { defaults.removeObject(forKey: key) }
    }
}
