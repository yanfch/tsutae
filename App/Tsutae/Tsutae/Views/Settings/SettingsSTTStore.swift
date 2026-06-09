import Combine
import SwiftUI
import TsutaeCore

enum RemoteCheckState: Equatable {
    case notTested
    case checking
    case saved
    case savedConfiguration
    case invalidBaseURL
    case missingModel
    case transcriptionSucceeded(String?)
    case failed(String)
    
    var isChecking: Bool {
        if case .checking = self {
            return true
        }
        return false
    }
    
    var isError: Bool {
        switch self {
        case .invalidBaseURL, .missingModel, .failed(_):
            return true
        default:
            return false
        }
    }
}

@MainActor
final class STTSettingsStore: ObservableObject {
    @Published private(set) var config: Config
    @Published private(set) var downloadStates: [String: STTDownloadState] = [:]
    @Published var filter: LocalSTTModelFilter = .all
    @Published var searchQuery = ""
    @Published var remoteCheckState: RemoteCheckState = .notTested
    
    private var activeDownloads: [String: Task<Void, Never>] = [:]
    private var modelPresentationOrder: [String: Int] = [:]
    
    init() {
        self.config = (try? ConfigLoader.load()) ?? .default
        refreshDownloadStates()
        rebuildModelPresentationOrder()
    }
    
    var filteredModels: [LocalSTTModelDescriptor] {
        LocalSTTModelCatalog.all
            .filter { descriptor in
                let matchesFilter: Bool = {
                    switch filter {
                    case .all:
                        return true
                    case .downloaded:
                        if case .downloaded = downloadStates[descriptor.id] ?? .notStarted {
                            return true
                        }
                        return false
                    case .auto:
                        return descriptor.group == .auto
                    case .chinese:
                        return descriptor.group == .chinese
                    case .english:
                        return descriptor.group == .english
                    case .preview:
                        return descriptor.group == .preview
                    }
                }()
                
                let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                let matchesSearch: Bool = query.isEmpty
                    || descriptor.displayName.localizedCaseInsensitiveContains(query)
                    || descriptor.summary.localizedCaseInsensitiveContains(query)
                    || descriptor.tags.joined(separator: " ").localizedCaseInsensitiveContains(query)
                
                return matchesFilter && matchesSearch
            }
            .sorted { lhs, rhs in
                let lhsOrder = modelPresentationOrder[lhs.id] ?? Int.max
                let rhsOrder = modelPresentationOrder[rhs.id] ?? Int.max
                if lhsOrder != rhsOrder {
                    return lhsOrder < rhsOrder
                }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
    }
    
    var availableModelCount: Int {
        LocalSTTModelCatalog.all.count
    }
    
    var downloadedCount: Int {
        downloadStates.values.filter {
            if case .downloaded = $0 { return true }
            return false
        }.count
    }
    
    var selectedModelID: String {
        config.stt.local.preferredModel ?? config.stt.model ?? "parakeet-tdt-v3"
    }
    
    var selectedModelTitle: String {
        LocalSTTModelCatalog.descriptor(id: selectedModelID)?.displayName ?? L10n.Settings.sttNotSelectedFallback
    }
    
    var selectedLanguageTitle: String {
        switch normalizedLanguage(config.stt.language) {
        case "zh":
            return L10n.Settings.languageChinese
        case "en":
            return L10n.Settings.languageEnglish
        default:
            return L10n.Settings.languageAuto
        }
    }
    
    var selectedLanguageBadgeTitle: String {
        switch normalizedLanguage(config.stt.language) {
        case "zh":
            return L10n.Settings.languageChinese
        case "en":
            return L10n.Settings.languageEnglish
        default:
            return L10n.Settings.sttLanguageAutoDetectBadge
        }
    }
    
    var modeTitle: String {
        switch config.stt.mode {
        case .localFirst:
            return L10n.Settings.sttModeLocalFirst
        case .remoteFirst:
            return L10n.Settings.sttModeRemoteFirst
        }
    }
    
    var fallbackTitle: String {
        switch config.stt.fallbackEngine {
        case "apple_speech":
            return L10n.Settings.sttFallbackAppleSpeechValue
        default:
            return L10n.Settings.sttDisabledValue
        }
    }
    
    var fallbackBadgeTitle: String {
        config.stt.fallbackEngine == nil ? L10n.Settings.sttNoFallback : L10n.Settings.sttFallbackOn
    }
    
    var keepLocalWarmedInRemoteFirstBadgeTitle: String {
        config.stt.local.keepModelWarmedInRemoteFirst ? L10n.Settings.sttKeepWarmBadge : L10n.Settings.sttUnloadWhenIdleBadge
    }
    
    var hasStoredRemoteAPIKey: Bool {
        config.stt.remote.apiKeyRef != nil
    }
    
    var isRemoteConfigured: Bool {
        remoteBaseURL.isEmpty == false && (config.stt.remote.model?.isEmpty == false)
    }
    
    var remoteSummaryTitle: String {
        if config.stt.remote.enabled == false {
            return L10n.Settings.sttOffShort
        }
        return isRemoteConfigured ? L10n.Settings.sttReadyShort : L10n.Settings.sttNeedsSetup
    }
    
    var remoteBaseURL: String {
        config.stt.remote.baseURL ?? ""
    }
    
    var modeBinding: Binding<String> {
        Binding(
            get: { self.config.stt.mode.rawValue },
            set: { [weak self] rawValue in
                guard let self, let mode = Config.STTRoutingMode(rawValue: rawValue) else { return }
                if mode == .remoteFirst, self.isRemoteConfigured == false {
                    return
                }
                self.config.stt.mode = mode
                self.save()
            }
        )
    }
    
    var languageBinding: Binding<String> {
        Binding(
            get: { self.normalizedLanguage(self.config.stt.language) ?? "auto" },
            set: { [weak self] value in
                guard let self else { return }
                self.config.stt.language = value == "auto" ? nil : value
                self.save()
            }
        )
    }
    
    var filterBinding: Binding<String> {
        Binding(
            get: { self.filter.rawValue },
            set: { [weak self] value in
                guard let self, let filter = LocalSTTModelFilter(rawValue: value) else { return }
                self.filter = filter
            }
        )
    }
    
    var fallbackEnabledBinding: Binding<Bool> {
        Binding(
            get: { self.config.stt.fallbackEngine != nil },
            set: { [weak self] value in
                self?.setFallbackEnabled(value)
            }
        )
    }
    
    func refreshDiskState() {
        refreshDownloadStates()
        rebuildModelPresentationOrder()
    }
    
    func setFallbackEnabled(_ isEnabled: Bool) {
        config.stt.fallbackEngine = isEnabled ? "apple_speech" : nil
        save()
    }
    
    func setRemoteEnabled(_ isEnabled: Bool) {
        config.stt.remote.enabled = isEnabled
        if config.stt.remote.enabled == false, config.stt.mode == .remoteFirst {
            config.stt.mode = .localFirst
        }
        save()
    }
    
    func setKeepLocalWarmedInRemoteFirst(_ isEnabled: Bool) {
        config.stt.local.keepModelWarmedInRemoteFirst = isEnabled
        save()
    }
    
    var keepLocalWarmedInRemoteFirstBinding: Binding<Bool> {
        Binding(
            get: { self.config.stt.local.keepModelWarmedInRemoteFirst },
            set: { [weak self] value in
                self?.setKeepLocalWarmedInRemoteFirst(value)
            }
        )
    }
    
    func loadRemoteAPIKey() -> String? {
        guard let ref = config.stt.remote.apiKeyRef else { return nil }
        return try? SecretsManager.get(ref)
    }
    
    func saveRemoteSettings(baseURL: String, model: String, requestStyleRawValue: String, apiKey: String) throws {
        config.stt.remote.baseURL = baseURL.nilIfBlank
        config.stt.remote.model = model.nilIfBlank
        config.stt.remote.requestStyle = Config.STTRemoteRequestStyle(rawValue: requestStyleRawValue) ?? .audioTranscriptions
        
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedAPIKey.isEmpty {
            // Keep the existing Keychain secret when the user did not explicitly edit the field.
        } else {
            let ref = config.stt.remote.apiKeyRef ?? "tsutae.remote_stt"
            try SecretsManager.set(trimmedAPIKey, for: ref)
            config.stt.remote.apiKeyRef = ref
        }
        
        if config.stt.remote.baseURL == nil, config.stt.mode == .remoteFirst {
            config.stt.mode = .localFirst
        }
        save()
    }
    
    func resolvedRemoteAPIKey(draft: String) -> String {
        let trimmedDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedDraft.isEmpty == false {
            return trimmedDraft
        }
        return loadRemoteAPIKey() ?? ""
    }
    
    func resetRemoteCheckState() {
        remoteCheckState = isRemoteConfigured ? .savedConfiguration : .notTested
    }
    
    func downloadState(for modelID: String) -> STTDownloadState {
        downloadStates[modelID] ?? .notStarted
    }
    
    func prepareLocalModelsPresentation() {
        rebuildModelPresentationOrder()
    }
    
    func canDeleteModel(_ modelID: String) -> Bool {
        if case .downloaded = downloadStates[modelID] ?? .notStarted {
            return true
        }
        return false
    }
    
    func replacementModelTitle(afterDeleting modelID: String) -> String {
        let replacementID = replacementModelID(afterDeleting: modelID)
        return LocalSTTModelCatalog.descriptor(id: replacementID)?.displayName ?? L10n.Settings.sttAnotherModelFallback
    }
    
    func selectModel(_ modelID: String) {
        config.stt.engine = "fluidaudio_local"
        config.stt.model = modelID
        config.stt.local.preferredModel = modelID
        if config.stt.local.downloadedModels.contains(modelID) == false, LocalSTTModelCatalog.isDownloaded(id: modelID) {
            config.stt.local.downloadedModels.append(modelID)
        }
        save()
        Task {
            try? await ConfiguredSTTRouter.prewarmLocalModel(config: self.config)
        }
    }
    
    func downloadModel(_ modelID: String) {
        if case .downloading = downloadStates[modelID] {
            return
        }
        
        activeDownloads[modelID]?.cancel()
        downloadStates[modelID] = .downloading(progress: 0)
        
        activeDownloads[modelID] = Task { [weak self] in
            guard let self else { return }
            do {
                try await LocalSTTModelCatalog.download(id: modelID) { progress in
                    Task { @MainActor [weak self] in
                        self?.updateDownloadProgress(for: modelID, candidate: progress)
                    }
                }
                self.updateDownloadProgress(for: modelID, candidate: 1)
                try? await Task.sleep(for: .milliseconds(900))
                if self.config.stt.local.downloadedModels.contains(modelID) == false {
                    self.config.stt.local.downloadedModels.append(modelID)
                }
                if self.config.stt.local.preferredModel == nil {
                    self.config.stt.local.preferredModel = modelID
                    self.config.stt.model = modelID
                }
                self.downloadStates[modelID] = .downloaded
                self.save()
                try? await ConfiguredSTTRouter.prewarmLocalModel(config: self.config)
            } catch {
                self.downloadStates[modelID] = .failed(error.localizedDescription)
            }
            self.activeDownloads[modelID] = nil
        }
    }
    
    func deleteModel(_ modelID: String) async throws {
        guard canDeleteModel(modelID) else { return }
        
        activeDownloads[modelID]?.cancel()
        activeDownloads[modelID] = nil
        
        let replacementID = replacementModelID(afterDeleting: modelID)
        try await LocalSTTModelCatalog.delete(id: modelID)
        
        config.stt.local.downloadedModels.removeAll { $0 == modelID }
        if config.stt.local.preferredModel == modelID {
            config.stt.local.preferredModel = replacementID
        }
        if config.stt.model == modelID {
            config.stt.model = replacementID
        }
        if config.stt.local.finalModel == modelID {
            config.stt.local.finalModel = replacementID
        }
        if config.stt.local.previewModel == modelID {
            config.stt.local.previewModel = replacementID
        }
        
        refreshDownloadStates()
        save()
    }
    
    func checkRemoteEndpoint(baseURL: String, model: String, requestStyleRawValue: String, apiKey: String, completion: @escaping (Bool) -> Void) {
        let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedBaseURL), trimmedBaseURL.isEmpty == false else {
            remoteCheckState = .invalidBaseURL
            completion(false)
            return
        }
        
        let requestStyle = Config.STTRemoteRequestStyle(rawValue: requestStyleRawValue) ?? .audioTranscriptions
        guard let resolvedModel = model.nilIfBlank else {
            remoteCheckState = .missingModel
            completion(false)
            return
        }
        
        remoteCheckState = .checking
        
        Task { [weak self] in
            do {
                let stt = OpenAICompatibleSTT(
                    baseURL: url,
                    model: resolvedModel,
                    apiKey: apiKey.nilIfBlank,
                    isLocal: false,
                    supportedLanguages: ["en"],
                    requestStyle: self?.requestStyle(for: requestStyle) ?? .audioTranscriptions
                )
                let transcript = try await stt.transcribe(SettingsRemoteProbeAudio.sample, language: "en")
                await MainActor.run {
                    let text = transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    self?.remoteCheckState = .transcriptionSucceeded(text.isEmpty ? nil : text)
                    completion(true)
                }
            } catch {
                await MainActor.run {
                    self?.remoteCheckState = .failed(error.localizedDescription)
                    completion(false)
                }
            }
        }
    }
    
    private func requestStyle(for style: Config.STTRemoteRequestStyle) -> OpenAICompatibleRequestStyle {
        switch style {
        case .audioTranscriptions:
            return .audioTranscriptions
        case .chatCompletionsAudio:
            return .chatCompletionsAudio
        }
    }
    
    private func refreshDownloadStates() {
        var resolvedDownloadedModels = config.stt.local.downloadedModels
        var didChangeDownloadedModels = false
        
        for descriptor in LocalSTTModelCatalog.all {
            if LocalSTTModelCatalog.isDownloaded(id: descriptor.id) {
                downloadStates[descriptor.id] = .downloaded
                if resolvedDownloadedModels.contains(descriptor.id) == false {
                    resolvedDownloadedModels.append(descriptor.id)
                    didChangeDownloadedModels = true
                }
            } else {
                downloadStates[descriptor.id] = .notStarted
            }
        }
        
        if didChangeDownloadedModels {
            config.stt.local.downloadedModels = resolvedDownloadedModels
            save()
        }
    }
    
    private func rebuildModelPresentationOrder() {
        let orderedIDs = LocalSTTModelCatalog.all
            .sorted { lhs, rhs in
                let lhsRank = initialModelSortRank(for: lhs.id)
                let rhsRank = initialModelSortRank(for: rhs.id)
                if lhsRank != rhsRank {
                    return lhsRank < rhsRank
                }
                if lhs.isRecommended != rhs.isRecommended {
                    return lhs.isRecommended && !rhs.isRecommended
                }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
            .map(\.id)
        
        modelPresentationOrder = Dictionary(
            uniqueKeysWithValues: orderedIDs.enumerated().map { index, id in (id, index) }
        )
    }
    
    private func initialModelSortRank(for modelID: String) -> Int {
        if modelID == selectedModelID {
            return 0
        }
        switch downloadStates[modelID] ?? .notStarted {
        case .downloaded:
            return 1
        case .downloading:
            return 2
        case .failed:
            return 3
        case .notStarted:
            return 4
        }
    }
    
    private func updateDownloadProgress(for modelID: String, candidate: Double) {
        guard case .downloading(let current) = downloadStates[modelID] ?? .notStarted else { return }
        let upperBound = candidate >= 1 ? 1.0 : 0.99
        let clamped = max(0, min(candidate, upperBound))
        downloadStates[modelID] = .downloading(progress: max(current, clamped))
    }
    
    private func replacementModelID(afterDeleting modelID: String) -> String {
        let orderedDescriptors = LocalSTTModelCatalog.all.sorted { lhs, rhs in
            let lhsOrder = modelPresentationOrder[lhs.id] ?? Int.max
            let rhsOrder = modelPresentationOrder[rhs.id] ?? Int.max
            if lhsOrder != rhsOrder {
                return lhsOrder < rhsOrder
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
        
        if let downloadedReplacement = orderedDescriptors.first(where: {
            guard $0.id != modelID else { return false }
            if case .downloaded = downloadStates[$0.id] ?? .notStarted {
                return true
            }
            return false
        }) {
            return downloadedReplacement.id
        }
        
        if let recommendedReplacement = LocalSTTModelCatalog.all.first(where: { $0.id != modelID && $0.isRecommended }) {
            return recommendedReplacement.id
        }
        
        return LocalSTTModelCatalog.all.first(where: { $0.id != modelID })?.id ?? modelID
    }
    
    private func save() {
        try? ConfigLoader.save(config)
        NotificationCenter.default.post(
            name: .tsutaeConfigDidChange,
            object: nil,
            userInfo: ["config": config]
        )
        LocalSTTResidencyCoordinator.shared.requestApply(config: config)
    }
    
    private func normalizedLanguage(_ language: String?) -> String? {
        switch language?.lowercased() {
        case nil, "", "auto":
            return nil
        case "zh", "zh-cn", "zh-hans":
            return "zh"
        case "en", "en-us", "en-gb":
            return "en"
        default:
            return language
        }
    }
}

enum LocalSTTModelFilter: String, CaseIterable {
    case all
    case downloaded
    case auto
    case chinese
    case english
    case preview
    
    var title: String {
        switch self {
        case .all:
            return L10n.Settings.sttFilterAllModels
        case .downloaded:
            return L10n.Settings.sttFilterDownloaded
        case .auto:
            return L10n.Settings.sttFilterAuto
        case .chinese:
            return L10n.Settings.sttFilterChinese
        case .english:
            return L10n.Settings.sttFilterEnglish
        case .preview:
            return L10n.Settings.sttFilterPreview
        }
    }
}

enum STTDownloadState: Equatable {
    case notStarted
    case downloading(progress: Double)
    case downloaded
    case failed(String)
}


