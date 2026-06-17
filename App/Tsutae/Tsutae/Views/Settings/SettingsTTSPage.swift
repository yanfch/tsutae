import AppKit
import AVFoundation
import SwiftUI
import TsutaeCore
import UniformTypeIdentifiers

private enum TTSRemoteCheckState: Equatable {
    case savedConfiguration
    case edited
    case checking
    case ready
    case saved
    case failed(String)

    var isChecking: Bool {
        if case .checking = self { return true }
        return false
    }
}

private struct TTSExportPayload: Equatable {
    let id = UUID()
    let data: Data
}

private struct TTSLocalModelDialog: Identifiable {
    enum Kind {
        case confirmDelete(LocalTTSModelDescriptor)
        case error(String)
    }

    let id = UUID()
    let kind: Kind
}

private enum TTSSettingsScreen {
    case overview
    case localModels
}

private enum TTSLocalModelFilter: String, CaseIterable {
    case all
    case downloaded
    case mandarin
    case english

    var title: String {
        switch self {
        case .all:
            return L10n.Settings.sttFilterAllModels
        case .downloaded:
            return L10n.Settings.sttFilterDownloaded
        case .mandarin:
            return L10n.Settings.ttsModelTagMandarin
        case .english:
            return L10n.Settings.ttsModelTagEnglish
        }
    }
}

struct TTSSettingsPage: View {
    @ObservedObject private var localTTSResidency = LocalTTSResidencyCoordinator.shared
    @State private var config = (try? ConfigLoader.load()) ?? .default
    @State private var previewText = "Tsutae can announce this update for you."
    @State private var playbackSnapshot = TTSPlaybackManager.shared.snapshot()
    @State private var remoteDraftBaseURL = ""
    @State private var remoteDraftModel = ""
    @State private var remoteDraftVoice = ""
    @State private var remoteDraftAPIKey = ""
    @State private var remoteDraftRequestStyle = Config.TTSRemoteRequestStyle.audioSpeech.rawValue
    @State private var remoteDraftInstructions = ""
    @State private var isRemoteConfigExpanded = false
    @State private var isRemoteAPIKeyRevealed = false
    @State private var remoteCheckState: TTSRemoteCheckState = .savedConfiguration
    @State private var previewStatusText: String?
    @State private var isExportingPreview = false
    @State private var exportPayload: TTSExportPayload?
    @State private var exportTask: Task<Void, Never>?
    @State private var screen: TTSSettingsScreen = .overview
    @State private var localModelSearchQuery = ""
    @State private var localModelFilter: TTSLocalModelFilter = .all
    @State private var localModelDialog: TTSLocalModelDialog?

    private let remoteEngineID = OpenAICompatibleRemoteTTSEngine.shared.id
    private let localEngineID = FluidAudioLocalTTSEngine.shared.id
    private let appleVoiceDefaultOptionID = "__default__"

    var body: some View {
        Group {
            switch screen {
            case .overview:
                overviewContent
            case .localModels:
                localModelsContent
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onAppear { refresh() }
        .onChange(of: remoteDraftSignature) { _, _ in
            if config.tts.remote.enabled {
                remoteCheckState = .edited
            }
        }
        .alert(item: $localModelDialog) { dialog in
            switch dialog.kind {
            case .confirmDelete(let descriptor):
                return Alert(
                    title: Text(deleteAlertTitle(for: descriptor)),
                    message: Text(deleteAlertMessage(for: descriptor)),
                    primaryButton: .destructive(Text(deleteAlertPrimaryActionTitle(for: descriptor))) {
                        Task {
                            await confirmDeleteLocalModel(descriptor)
                        }
                    },
                    secondaryButton: .cancel()
                )
            case .error(let message):
                return Alert(
                    title: Text(L10n.Settings.sttDeleteErrorTitle),
                    message: Text(message),
                    dismissButton: .default(Text(L10n.Common.dismiss))
                )
            }
        }
        .background(
            TTSExportSavePanelPresenter(
                payload: $exportPayload,
                statusText: $previewStatusText,
                isExporting: $isExportingPreview
            )
            .frame(width: 0, height: 0)
        )
        .onReceive(NotificationCenter.default.publisher(for: .tsutaeTTSPlaybackDidChange)) { _ in
            playbackSnapshot = TTSPlaybackManager.shared.snapshot()
            if LocalTTSModelCatalog.isKnownVoiceID(playbackSnapshot.voiceID) {
                localTTSResidency.refreshReadyState()
            }
        }
    }

    private var overviewContent: some View {
        VStack(alignment: .leading, spacing: SettingsTokens.Spacing.section) {
            SettingsDashboardCard(title: L10n.Settings.ttsCurrentVoiceTitle, subtitle: L10n.Settings.ttsCurrentVoiceSubtitle) {
                VStack(alignment: .leading, spacing: SettingsTokens.Spacing.content) {
                    SettingsStackedControlRow(label: L10n.Settings.ttsRouteLabel) {
                        SettingsDropdown(
                            selection: routeSelection,
                            options: routeOptions,
                            tone: .active,
                            width: SettingsTokens.Width.modeDropdown,
                            menuWidth: SettingsTokens.Width.modeDropdown
                        )
                    }

                    SettingsStackedControlRow(label: L10n.Settings.sttRemoteModelLabel) {
                        if isLocalSelected {
                            SettingsDropdown(
                                selection: localModelSelection,
                                options: localModelOptions,
                                tone: .soft,
                                width: SettingsTokens.Size.remoteFieldWidth,
                                menuWidth: SettingsTokens.Size.remoteFieldWidth
                            )
                        } else if isRemoteSelected {
                            ServerStatusCapsule(title: currentModelSummary, tone: isRemoteReady ? .active : .soft)
                        } else {
                            Text(currentModelSummary)
                                .font(DS.font.mono(size: 12, weight: .regular))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundStyle(.secondary)
                        }
                    }

                    SettingsStackedControlRow(label: L10n.Settings.labelVoice) {
                        if isRemoteSelected {
                            ServerStatusCapsule(title: currentVoiceSummary, tone: remoteVoiceFromConfig == nil ? .soft : .active)
                        } else if isLocalSelected {
                            SettingsDropdown(
                                selection: localVoiceSelection,
                                options: localVoiceOptions(for: selectedLocalModel),
                                tone: .soft,
                                width: SettingsTokens.Size.remoteFieldWidth,
                                menuWidth: SettingsTokens.Size.remoteFieldWidth,
                                maxMenuHeight: 280
                            )
                        } else {
                            SettingsDropdown(
                                selection: activeVoiceSelection,
                                options: activeVoiceOptions,
                                tone: .soft,
                                width: SettingsTokens.Size.remoteFieldWidth,
                                menuWidth: SettingsTokens.Size.remoteFieldWidth,
                                maxMenuHeight: 280
                            )
                        }
                    }

                    SettingsStackedControlRow(label: L10n.Settings.labelSpeed) {
                        if isRemoteSelected {
                            ServerStatusCapsule(title: L10n.Settings.ttsRateProviderManaged, tone: .soft)
                        } else {
                            TTSRateControl(rate: rateBinding)
                        }
                    }
                }
            }

            SettingsDashboardCard(title: L10n.Settings.ttsLocalSectionTitle, subtitle: L10n.Settings.ttsLocalSectionSubtitle) {
                VStack(alignment: .leading, spacing: SettingsTokens.Spacing.content) {
                    HStack(spacing: 8) {
                        ServerStatusCapsule(title: selectedLocalModelTitle, tone: config.tts.local.enabled ? .active : .soft)
                        ServerStatusCapsule(title: localModelStateTitle(for: selectedLocalModel), tone: localModelStateTone(for: selectedLocalModel))
                    }

                    SettingsKeyValueList(rows: [
                        (L10n.Settings.sttSelectedModelLabel, selectedLocalModelTitle),
                        (L10n.Settings.sttDownloadedLabel, L10n.Settings.ttsDownloadedCount(cachedLocalModelCount)),
                        (L10n.Settings.sttNextStepLabel, L10n.Settings.ttsManageModelsValue)
                    ])

                    HStack(spacing: 10) {
                        Button(L10n.Settings.sttManageModelsButton) {
                            localTTSResidency.refreshReadyState()
                            screen = .localModels
                        }
                        .buttonStyle(SettingsAccentButtonStyle())

                        Button(L10n.Settings.sttRefreshButton) {
                            localTTSResidency.refreshReadyState()
                        }
                        .buttonStyle(.bordered)
                    }

                    SettingsFeatureToggleRow(
                        title: L10n.Settings.ttsLocalUseTitle,
                        subtitle: config.tts.local.enabled ? L10n.Settings.ttsLocalUseEnabledSubtitle : L10n.Settings.ttsLocalUseDisabledSubtitle,
                        isOn: localEnabledBinding,
                        badgeTitle: config.tts.local.enabled ? L10n.Settings.toggleOn : L10n.Settings.sttOffShort,
                        badgeTone: config.tts.local.enabled ? .active : .neutral
                    )

                    if localTTSResidency.warmingVoiceID == selectedLocalModel.voiceID {
                        SettingsInlineStatusMessage(
                            text: L10n.Settings.ttsWarmingModel(selectedLocalModel.displayName),
                            tone: .info
                        )
                    } else if let error = localTTSResidency.lastError {
                        SettingsInlineStatusMessage(text: error, tone: .danger)
                    }
                }
            }

            SettingsDashboardCard(title: L10n.Settings.ttsRemoteSectionTitle, subtitle: L10n.Settings.ttsRemoteSectionSubtitle) {
                VStack(alignment: .leading, spacing: SettingsTokens.Spacing.content) {
                    SettingsFeatureToggleRow(
                        title: L10n.Settings.ttsRemoteUseTitle,
                        subtitle: config.tts.remote.enabled ? L10n.Settings.ttsRemoteUseEnabledSubtitle : L10n.Settings.ttsRemoteUseDisabledSubtitle,
                        isOn: remoteEnabledBinding,
                        badgeTitle: remoteBadgeTitle,
                        badgeTone: config.tts.remote.enabled ? .active : .neutral,
                        trailing: {
                            if config.tts.remote.enabled {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        isRemoteConfigExpanded.toggle()
                                    }
                                } label: {
                                    Image(systemName: isRemoteConfigExpanded ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .buttonStyle(SettingsCircularIconButtonStyle())
                            }
                        }
                    )

                    if config.tts.remote.enabled && isRemoteConfigExpanded {
                        SettingsSection(title: L10n.Settings.sttRemoteConnectionTitle) {
                            SettingsFormRow(label: L10n.Settings.sttRemoteProtocolLabel) {
                                SettingsDropdown(
                                    selection: $remoteDraftRequestStyle,
                                    options: [
                                        .init(id: Config.TTSRemoteRequestStyle.audioSpeech.rawValue, title: L10n.Settings.ttsRemoteProtocolAudioSpeech),
                                        .init(id: Config.TTSRemoteRequestStyle.chatCompletionsAudio.rawValue, title: L10n.Settings.sttRemoteProtocolChatAudio)
                                    ],
                                    tone: .soft,
                                    width: SettingsTokens.Size.remoteFieldWidth,
                                    menuWidth: SettingsTokens.Width.remoteProtocolMenu
                                )
                            }
                            SettingsDivider()
                            SettingsFormRow(label: L10n.Settings.sttRemoteBaseURLLabel) {
                                SettingsInlineTextField(text: $remoteDraftBaseURL, placeholder: L10n.Settings.sttRemoteBaseURLPlaceholder, width: SettingsTokens.Size.remoteFieldWidth)
                            }
                            SettingsDivider()
                            SettingsFormRow(label: L10n.Settings.sttRemoteModelLabel) {
                                SettingsInlineTextField(text: $remoteDraftModel, placeholder: L10n.Settings.sttRemoteModelPlaceholder, width: SettingsTokens.Size.remoteFieldWidth)
                            }
                            SettingsDivider()
                            SettingsFormRow(label: L10n.Settings.labelVoice) {
                                SettingsInlineTextField(text: $remoteDraftVoice, placeholder: L10n.Settings.ttsRemoteVoicePlaceholder, width: SettingsTokens.Size.remoteFieldWidth)
                            }
                            SettingsDivider()
                            TTSMultilineFormRow(label: L10n.Settings.ttsRemoteInstructionsLabel) {
                                SettingsInlineMultilineTextField(text: $remoteDraftInstructions, placeholder: L10n.Settings.ttsRemoteInstructionsPlaceholder, width: SettingsTokens.Size.remoteFieldWidth)
                            }
                            SettingsDivider()
                            SettingsFormRow(label: L10n.Settings.sttRemoteAPIKeyLabel, helpText: L10n.Settings.sttRemoteAPIKeyHelp) {
                                SettingsInlineSecureField(
                                    text: $remoteDraftAPIKey,
                                    isRevealed: $isRemoteAPIKeyRevealed,
                                    placeholder: remoteAPIKeyPlaceholder,
                                    width: SettingsTokens.Size.remoteFieldWidth,
                                    onReveal: {
                                        if remoteDraftAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                            remoteDraftAPIKey = loadRemoteAPIKey() ?? ""
                                        }
                                    }
                                )
                            }
                        }

                        HStack(spacing: 10) {
                            ServerStatusCapsule(title: remoteFeedbackText, tone: remoteFeedbackTone)
                            Spacer(minLength: 0)
                            Button(remoteCheckState.isChecking ? L10n.Settings.sttRemoteCheckingButton : L10n.Settings.sttRemoteTestButton) {
                                testRemoteSettings()
                            }
                            .buttonStyle(.bordered)
                            .disabled(canRunRemoteAction == false || remoteCheckState.isChecking)

                            Button(L10n.Settings.sttRemoteSaveButton) {
                                saveRemoteSettings()
                            }
                            .buttonStyle(SettingsAccentButtonStyle())
                            .disabled(canRunRemoteAction == false || remoteCheckState.isChecking)
                        }
                    }
                }
            }

            SettingsDashboardCard(title: L10n.Settings.ttsPreviewTitle, subtitle: L10n.Settings.ttsPreviewSubtitle) {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.Settings.ttsPreviewTextLabel)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        SettingsInlineMultilineTextField(text: $previewText, placeholder: L10n.Settings.ttsPreviewPlaceholder, width: SettingsTokens.Size.remoteFieldWidth)
                    }
                    HStack(spacing: 10) {
                        Button(playbackSnapshot.state == .idle ? L10n.Settings.ttsPreviewPlayButton : L10n.Settings.ttsPreviewStopButton) {
                            if playbackSnapshot.state == .idle {
                                triggerPreview()
                            } else {
                                TTSPlaybackManager.shared.stop()
                            }
                        }
                        .buttonStyle(SettingsAccentButtonStyle())

                        Button(isExportingPreview ? L10n.Settings.ttsPreviewCancelExportButton : L10n.Settings.ttsPreviewExportButton) {
                            if isExportingPreview {
                                cancelPreviewExport()
                            } else {
                                exportPreviewWAV()
                            }
                        }
                        .buttonStyle(.bordered)

                        ServerStatusCapsule(
                            title: previewStatusText ?? playbackStatusText,
                            tone: playbackSnapshot.state == .idle ? .soft : .active
                        )
                    }
                }
            }

            SettingsDashboardCard(title: L10n.Settings.ttsPlaybackTitle, subtitle: L10n.Settings.ttsPlaybackSubtitle) {
                VStack(spacing: 0) {
                    SettingsFormRow(label: L10n.Settings.ttsInterruptCurrentLabel) {
                        SettingsChipSelector(
                            selection: interruptSelection,
                            options: [
                                ("off", L10n.Settings.toggleOff),
                                ("on", L10n.Settings.toggleOn)
                            ]
                        )
                    }
                    SettingsDivider()
                    SettingsFormRow(label: L10n.Settings.ttsQueueWhenBusyLabel, helpText: queueHelpText) {
                        SettingsChipSelector(
                            selection: queueSelection,
                            options: [
                                ("off", L10n.Settings.toggleOff),
                                ("on", L10n.Settings.toggleOn)
                            ]
                        )
                        .disabled(config.tts.interruptCurrent)
                        .opacity(config.tts.interruptCurrent ? 0.45 : 1)
                    }
                }
            }

            SettingsDashboardCard(title: L10n.Settings.ttsFallbackTitle, subtitle: L10n.Settings.ttsFallbackSubtitle) {
                SettingsFeatureToggleRow(
                    title: L10n.Settings.ttsFallbackAppleTitle,
                    subtitle: L10n.Settings.ttsFallbackAppleSubtitle,
                    isOn: fallbackEnabledBinding,
                    badgeTitle: config.tts.fallbackEngine == AppleTTSEngine.shared.id ? L10n.Settings.sttFallbackOn : L10n.Settings.sttNoFallback,
                    badgeTone: config.tts.fallbackEngine == AppleTTSEngine.shared.id ? .active : .neutral
                )
            }
        }
    }

    private var localModelsContent: some View {
        VStack(alignment: .leading, spacing: SettingsTokens.Spacing.card) {
            HStack(spacing: 12) {
                Button {
                    screen = .overview
                } label: {
                    Label(L10n.Settings.ttsBackToTTS, systemImage: "chevron.left")
                }
                .buttonStyle(SettingsGhostButtonStyle())

                Spacer(minLength: 0)

                ServerStatusCapsule(title: L10n.Settings.ttsDownloadedCount(cachedLocalModelCount), tone: .soft)
                ServerStatusCapsule(title: selectedLocalModelTitle, tone: .active)
            }

            SettingsDashboardCard(title: L10n.Settings.ttsLocalModelsTitle, subtitle: L10n.Settings.ttsLocalModelsSubtitle) {
                VStack(alignment: .leading, spacing: SettingsTokens.Spacing.content) {
                    SettingsKeyValueList(rows: [
                        (L10n.Settings.sttSelectedLabel, selectedLocalModelTitle),
                        (L10n.Settings.sttAvailableLabel, L10n.Settings.ttsCuratedModelsCount(LocalTTSModelCatalog.all.count)),
                        (L10n.Settings.sttDownloadedLabel, L10n.Settings.ttsDownloadedCount(cachedLocalModelCount)),
                        (L10n.Settings.ttsWarmStatusLabel, localModelStateTitle(for: selectedLocalModel))
                    ])

                    HStack(spacing: 10) {
                        SettingsSearchField(text: $localModelSearchQuery)

                        SettingsDropdown(
                            selection: localModelFilterBinding,
                            options: TTSLocalModelFilter.allCases.map { filter in
                                .init(id: filter.rawValue, title: filter.title)
                            },
                            tone: .soft,
                            width: SettingsTokens.Width.modelFilterDropdown
                        )

                        Button(L10n.Settings.sttRefreshButton) {
                            localTTSResidency.refreshReadyState()
                        }
                        .buttonStyle(.bordered)
                    }

                    if localTTSResidency.warmingVoiceID == selectedLocalModel.voiceID {
                        SettingsInlineStatusMessage(
                            text: L10n.Settings.ttsWarmingModel(selectedLocalModel.displayName),
                            tone: .info
                        )
                    } else if let error = localTTSResidency.lastError {
                        SettingsInlineStatusMessage(text: error, tone: .danger)
                    }
                }
            }

            SettingsDashboardCard(title: L10n.Settings.ttsModelLibraryTitle, subtitle: L10n.Settings.ttsModelLibrarySubtitle) {
                SettingsTwoColumnGrid {
                    ForEach(filteredLocalModels) { descriptor in
                        TTSLocalModelCard(
                            descriptor: descriptor,
                            isSelected: selectedLocalModel.voiceID == descriptor.voiceID,
                            isCached: LocalTTSModelCatalog.isCached(id: descriptor.id),
                            isReady: localTTSResidency.readyVoiceIDs.contains(descriptor.voiceID),
                            isWarming: localTTSResidency.warmingVoiceID == descriptor.voiceID,
                            downloadProgress: localTTSResidency.warmProgressByVoiceID[descriptor.voiceID],
                            onUse: { selectLocalModel(descriptor) },
                            onPreload: { localTTSResidency.requestWarm(voiceID: descriptor.voiceID) },
                            onTest: { testLocalModel(descriptor) },
                            onDelete: canDeleteLocalModel(descriptor) ? {
                                promptDeleteLocalModel(descriptor)
                            } : nil
                        )
                    }
                }
            }
        }
    }

    private var isRemoteSelected: Bool {
        config.tts.engine == remoteEngineID
    }

    private var isLocalSelected: Bool {
        config.tts.engine == localEngineID
    }

    private var isRemoteReady: Bool {
        config.tts.remote.enabled
            && config.tts.remote.baseURL?.nilIfBlank != nil
            && config.tts.remote.model?.nilIfBlank != nil
    }

    private var routeOptions: [SettingsDropdownOption] {
        [
            .init(id: localEngineID, title: L10n.Settings.ttsRouteLocal, isDisabled: config.tts.local.enabled == false),
            .init(id: remoteEngineID, title: L10n.Settings.ttsRouteRemote, isDisabled: isRemoteReady == false),
            .init(id: AppleTTSEngine.shared.id, title: L10n.Settings.ttsRouteApple)
        ]
    }

    private var routeSelection: Binding<String> {
        Binding(
            get: { config.tts.engine },
            set: { newValue in
                guard canSelectRoute(newValue) else { return }
                updateConfig {
                    $0.tts.engine = newValue
                    if newValue == localEngineID, LocalTTSModelCatalog.isKnownVoiceID($0.tts.voice) == false {
                        $0.tts.voice = selectedLocalModel.voiceID
                    }
                }
                if newValue == localEngineID {
                    localTTSResidency.requestWarm(voiceID: selectedLocalModel.voiceID)
                }
            }
        )
    }

    private func canSelectRoute(_ engineID: String) -> Bool {
        if engineID == localEngineID {
            return config.tts.local.enabled
        }
        if engineID == remoteEngineID {
            return isRemoteReady
        }
        return engineID == AppleTTSEngine.shared.id
    }

    private var currentProviderTitle: String {
        if isRemoteSelected { return L10n.Settings.ttsProviderRemote }
        if isLocalSelected { return L10n.Settings.ttsProviderLocal }
        return L10n.Settings.ttsProviderApple
    }

    private var currentProviderTone: ServerStatusCapsule.Tone {
        isRemoteSelected || isLocalSelected ? .active : .neutral
    }

    private var currentRouteSummary: String {
        if isRemoteSelected { return L10n.Settings.ttsModeOneShot }
        if isLocalSelected { return L10n.Settings.valueLocal }
        return L10n.Settings.valueSystem
    }

    private var currentRouteTone: ServerStatusCapsule.Tone {
        isLocalSelected ? .active : .soft
    }

    private var currentModelSummary: String {
        if isRemoteSelected {
            return config.tts.remote.model?.nilIfBlank ?? L10n.Settings.sttNotSetFallback
        }
        if isLocalSelected {
            return L10n.Settings.ttsLocalModelKokoroAne
        }
        return L10n.Settings.valueSystem
    }

    private var currentVoiceSummary: String {
        let trimmed = ((isRemoteSelected ? remoteVoiceFromConfig : config.tts.voice) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return isLocalSelected ? L10n.Settings.ttsVoiceAutomatic : L10n.Settings.valueDefault
        }
        if isLocalSelected {
            return localVoiceDisplayName(for: trimmed) ?? trimmed
        }
        return appleVoiceDisplayName(for: trimmed) ?? trimmed
    }

    private var selectedLocalModel: LocalTTSModelDescriptor {
        LocalTTSModelCatalog.descriptor(voiceID: config.tts.voice) ?? LocalTTSModelCatalog.all[0]
    }

    private var selectedLocalModelTitle: String {
        selectedLocalModel.displayName
    }

    private var cachedLocalModelCount: Int {
        LocalTTSModelCatalog.all.filter { LocalTTSModelCatalog.isCached(id: $0.id) }.count
    }

    private var localModelFilterBinding: Binding<String> {
        Binding(
            get: { localModelFilter.rawValue },
            set: { value in
                guard let filter = TTSLocalModelFilter(rawValue: value) else { return }
                localModelFilter = filter
            }
        )
    }

    private var filteredLocalModels: [LocalTTSModelDescriptor] {
        LocalTTSModelCatalog.all.filter { descriptor in
            matchesLocalModelFilter(descriptor) && matchesLocalModelSearch(descriptor)
        }
    }

    private func matchesLocalModelFilter(_ descriptor: LocalTTSModelDescriptor) -> Bool {
        switch localModelFilter {
        case .all:
            return true
        case .downloaded:
            return LocalTTSModelCatalog.isCached(id: descriptor.id)
        case .mandarin:
            return descriptor.language.lowercased().hasPrefix("zh")
        case .english:
            return descriptor.language.lowercased().hasPrefix("en")
        }
    }

    private func matchesLocalModelSearch(_ descriptor: LocalTTSModelDescriptor) -> Bool {
        let query = localModelSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard query.isEmpty == false else { return true }
        return localModelSearchFields(for: descriptor).contains { field in
            field.lowercased().contains(query)
        }
    }

    private func localModelSearchFields(for descriptor: LocalTTSModelDescriptor) -> [String] {
        [
            descriptor.id,
            descriptor.voiceID,
            descriptor.displayName,
            descriptor.runtime,
            descriptor.language,
            descriptor.summary,
            descriptor.size,
            descriptor.memory,
            descriptor.tags.joined(separator: " "),
            localizedLocalModelSummary(for: descriptor),
            descriptor.tags.map(localizedLocalModelTag).joined(separator: " ")
        ]
    }

    private func localModelStateTitle(for descriptor: LocalTTSModelDescriptor) -> String {
        if localTTSResidency.warmingVoiceID == descriptor.voiceID {
            return L10n.Settings.sttModelBadgeWarming
        }
        if localTTSResidency.readyVoiceIDs.contains(descriptor.voiceID) {
            return L10n.Settings.sttReadyShort
        }
        if LocalTTSModelCatalog.isCached(id: descriptor.id) {
            return L10n.Settings.sttModelBadgeDownloaded
        }
        return L10n.Settings.sttModelStatusNotDownloaded
    }

    private func localModelStateTone(for descriptor: LocalTTSModelDescriptor) -> ServerStatusCapsule.Tone {
        if localTTSResidency.warmingVoiceID == descriptor.voiceID || localTTSResidency.readyVoiceIDs.contains(descriptor.voiceID) {
            return .active
        }
        return LocalTTSModelCatalog.isCached(id: descriptor.id) ? .soft : .neutral
    }

    private var appleVoiceOptions: [SettingsDropdownOption] {
        [SettingsDropdownOption(id: appleVoiceDefaultOptionID, title: L10n.Settings.ttsVoiceAutomatic)] + AppleTTSEngine.shared.voices.map {
            SettingsDropdownOption(id: $0.id, title: "\($0.displayName) · \($0.language)")
        }
    }

    private var localModelOptions: [SettingsDropdownOption] {
        LocalTTSModelCatalog.all.map {
            SettingsDropdownOption(id: $0.id, title: $0.displayName)
        }
    }

    private var localModelSelection: Binding<String> {
        Binding(
            get: { selectedLocalModel.id },
            set: { newValue in
                guard let descriptor = LocalTTSModelCatalog.descriptor(id: newValue) else { return }
                updateConfig {
                    $0.tts.voice = descriptor.voiceID
                }
                localTTSResidency.requestWarm(voiceID: descriptor.voiceID)
            }
        )
    }

    private func localVoiceOptions(for descriptor: LocalTTSModelDescriptor) -> [SettingsDropdownOption] {
        [SettingsDropdownOption(id: appleVoiceDefaultOptionID, title: L10n.Settings.ttsVoiceAutomatic)] + descriptor.voices.map {
            SettingsDropdownOption(id: $0.id, title: localVoiceOptionTitle($0))
        }
    }

    private var activeVoiceOptions: [SettingsDropdownOption] {
        appleVoiceOptions
    }

    private var activeVoiceSelection: Binding<String> {
        Binding(
            get: {
                let voice = (config.tts.voice ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return voice.isEmpty ? appleVoiceDefaultOptionID : voice
            },
            set: { newValue in
                updateConfig {
                    $0.tts.voice = newValue == appleVoiceDefaultOptionID ? nil : newValue
                }
            }
        )
    }

    private var remoteVoiceFromConfig: String? {
        config.tts.remote.voice?.nilIfBlank
            ?? legacyRemoteVoice(from: config.tts.voice)
    }

    private var currentPlaybackVoiceID: String? {
        isRemoteSelected ? remoteVoiceFromConfig : config.tts.voice
    }

    private func legacyRemoteVoice(from voiceID: String?) -> String? {
        guard let voiceID = voiceID?.nilIfBlank else {
            return nil
        }
        return LocalTTSModelCatalog.isKnownVoiceID(voiceID) ? nil : voiceID
    }

    private var localVoiceSelection: Binding<String> {
        Binding(
            get: {
                let voice = (config.tts.voice ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard voice.isEmpty == false, voice != selectedLocalModel.voiceID else {
                    return appleVoiceDefaultOptionID
                }
                return selectedLocalModel.voices.contains(where: { $0.id == voice }) ? voice : appleVoiceDefaultOptionID
            },
            set: { newValue in
                updateConfig {
                    $0.tts.voice = newValue == appleVoiceDefaultOptionID ? selectedLocalModel.voiceID : newValue
                }
                localTTSResidency.requestWarm(voiceID: newValue == appleVoiceDefaultOptionID ? selectedLocalModel.voiceID : newValue)
            }
        )
    }

    private var rateBinding: Binding<Double> {
        Binding(
            get: { config.tts.rate },
            set: { newValue in
                updateConfig { $0.tts.rate = max(0.5, min(newValue, 2.0)) }
            }
        )
    }

    private var remoteBadgeTitle: String {
        guard config.tts.remote.enabled else { return L10n.Settings.sttOffShort }
        return (config.tts.remote.baseURL?.nilIfBlank != nil && config.tts.remote.model?.nilIfBlank != nil) ? L10n.Settings.sttReadyShort : L10n.Settings.sttNeedsSetup
    }

    private var remoteFeedbackText: String {
        switch remoteCheckState {
        case .savedConfiguration:
            return L10n.Settings.sttRemoteFeedbackSavedConfiguration
        case .edited:
            return L10n.Settings.sttRemoteFeedbackEdited
        case .checking:
            return L10n.Settings.sttRemoteFeedbackChecking
        case .ready:
            return L10n.Settings.ttsRemoteFeedbackReady
        case .saved:
            return L10n.Settings.sttRemoteFeedbackSaved
        case .failed(let message):
            return message
        }
    }

    private var remoteFeedbackTone: ServerStatusCapsule.Tone {
        switch remoteCheckState {
        case .ready, .saved:
            return .active
        case .failed:
            return .warning
        case .checking, .edited, .savedConfiguration:
            return .soft
        }
    }

    private var remoteAPIKeyPlaceholder: String {
        config.tts.remote.apiKeyRef == nil ? "sk-…" : L10n.Settings.sttRemoteAPIKeyStoredPlaceholder
    }

    private var canRunRemoteAction: Bool {
        remoteDraftBaseURL.nilIfBlank != nil && remoteDraftModel.nilIfBlank != nil
    }

    private var playbackStatusText: String {
        let base: String
        switch playbackSnapshot.state {
        case .idle:
            base = L10n.Settings.ttsStatusIdle
        case .preparing:
            base = L10n.Settings.ttsStatusPreparing
        case .queued:
            base = L10n.Settings.notifyQueued
        case .speaking, .stopping:
            base = L10n.Settings.ttsStatusSpeaking
        }
        guard playbackSnapshot.queueLength > 0 else { return base }
        return "\(base) · +\(playbackSnapshot.queueLength)"
    }

    private var remoteDraftSignature: String {
        [remoteDraftBaseURL, remoteDraftModel, remoteDraftVoice, remoteDraftRequestStyle, remoteDraftInstructions, remoteDraftAPIKey]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: "|")
    }

    private var remoteEnabledBinding: Binding<Bool> {
        Binding(
            get: { config.tts.remote.enabled },
            set: { newValue in
                if newValue {
                    syncRemoteDraftFromConfig()
                }
                updateConfig {
                    $0.tts.remote.enabled = newValue
                    if newValue == false, $0.tts.engine == remoteEngineID {
                        $0.tts.engine = fallbackRouteForDisabledRemote(config: $0.tts)
                    }
                }
                withAnimation(.easeInOut(duration: 0.18)) {
                    isRemoteConfigExpanded = newValue
                }
            }
        )
    }

    private var localEnabledBinding: Binding<Bool> {
        Binding(
            get: { config.tts.local.enabled },
            set: { newValue in
                updateConfig {
                    $0.tts.local.enabled = newValue
                    if newValue == false, $0.tts.engine == localEngineID {
                        $0.tts.engine = fallbackRouteForDisabledLocal(config: $0.tts)
                    }
                }
            }
        )
    }

    private func fallbackRouteForDisabledLocal(config: Config.TTSConfig) -> String {
        if config.remote.enabled,
           config.remote.baseURL?.nilIfBlank != nil,
           config.remote.model?.nilIfBlank != nil {
            return remoteEngineID
        }
        return AppleTTSEngine.shared.id
    }

    private func fallbackRouteForDisabledRemote(config: Config.TTSConfig) -> String {
        config.local.enabled ? localEngineID : AppleTTSEngine.shared.id
    }

    private var fallbackEnabledBinding: Binding<Bool> {
        Binding(
            get: { config.tts.fallbackEngine == AppleTTSEngine.shared.id },
            set: { newValue in
                updateConfig { $0.tts.fallbackEngine = newValue ? AppleTTSEngine.shared.id : nil }
            }
        )
    }

    private var interruptSelection: Binding<String> {
        Binding(
            get: { config.tts.interruptCurrent ? "on" : "off" },
            set: { newValue in
                updateConfig { $0.tts.interruptCurrent = newValue == "on" }
            }
        )
    }

    private var queueSelection: Binding<String> {
        Binding(
            get: { config.tts.queueWhenBusy ? "on" : "off" },
            set: { newValue in
                updateConfig { $0.tts.queueWhenBusy = newValue == "on" }
            }
        )
    }

    private var queueHelpText: String {
        config.tts.interruptCurrent ? L10n.Settings.ttsQueueDisabledHelp : L10n.Settings.ttsQueueWhenBusyHelp
    }

    private func refresh() {
        config = (try? ConfigLoader.load()) ?? .default
        playbackSnapshot = TTSPlaybackManager.shared.snapshot()
        localTTSResidency.refreshReadyState()
        syncRemoteDraftFromConfig()
        remoteCheckState = .savedConfiguration
    }

    private func syncRemoteDraftFromConfig() {
        remoteDraftBaseURL = config.tts.remote.baseURL ?? ""
        remoteDraftModel = config.tts.remote.model ?? ""
        remoteDraftVoice = remoteVoiceFromConfig ?? ""
        remoteDraftRequestStyle = config.tts.remote.requestStyle.rawValue
        remoteDraftInstructions = config.tts.remote.instructions ?? ""
        remoteDraftAPIKey = ""
        isRemoteAPIKeyRevealed = false
        previewStatusText = nil
    }

    private func effectiveRemoteConfig() -> Config.TTSConfig {
        var effective = config.tts
        effective.engine = remoteEngineID
        effective.remote.enabled = true
        effective.remote.baseURL = remoteDraftBaseURL.nilIfBlank
        effective.remote.model = remoteDraftModel.nilIfBlank
        effective.remote.requestStyle = Config.TTSRemoteRequestStyle(rawValue: remoteDraftRequestStyle) ?? .audioSpeech
        effective.remote.instructions = remoteDraftInstructions.nilIfBlank
        effective.remote.voice = remoteDraftVoice.nilIfBlank
        return effective
    }

    private func loadRemoteAPIKey() -> String? {
        guard let ref = config.tts.remote.apiKeyRef else { return nil }
        return try? SecretsManager.get(ref)
    }

    private func resolvedRemoteAPIKeyForAction() -> String? {
        let trimmedDraft = remoteDraftAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedDraft.isEmpty == false { return trimmedDraft }
        return loadRemoteAPIKey()
    }

    private func testRemoteSettings() {
        guard canRunRemoteAction else { return }
        remoteCheckState = .checking
        let effective = effectiveRemoteConfig()
        let apiKey = resolvedRemoteAPIKeyForAction()
        Task {
            do {
                _ = try await OpenAICompatibleRemoteTTSEngine.shared.synthesize(
                    "Tsutae remote voice check.",
                    voiceID: effective.remote.voice,
                    instructions: effective.remote.instructions,
                    config: effective,
                    apiKeyOverride: apiKey
                )
                await MainActor.run { remoteCheckState = .ready }
            } catch {
                await MainActor.run { remoteCheckState = .failed(error.localizedDescription) }
            }
        }
    }

    private func appleVoiceDisplayName(for voiceID: String) -> String? {
        AppleTTSEngine.shared.voices.first(where: { $0.id == voiceID }).map { "\($0.displayName) · \($0.language)" }
    }

    private func localVoiceDisplayName(for voiceID: String) -> String? {
        FluidAudioLocalTTSEngine.shared.voices.first(where: { $0.id == voiceID }).map { "\($0.displayName) · \($0.language)" }
    }

    private func localVoiceOptionTitle(_ voice: LocalTTSVoiceDescriptor) -> String {
        let prefix = voice.isDefault ? L10n.Settings.ttsDefaultVoiceLabel : voice.displayName
        return "\(prefix) · \(voice.upstreamVoiceID) · \(voice.language)"
    }

    private func localizedLocalModelSummary(for descriptor: LocalTTSModelDescriptor) -> String {
        switch descriptor.id {
        case "kokoro-ane-mandarin":
            return L10n.Settings.ttsModelSummaryKokoroMandarin
        case "kokoro-ane-english":
            return L10n.Settings.ttsModelSummaryKokoroEnglish
        default:
            return descriptor.summary
        }
    }

    private func localizedLocalModelTag(_ tag: String) -> String {
        switch tag {
        case "Mandarin":
            return L10n.Settings.ttsModelTagMandarin
        case "English":
            return L10n.Settings.ttsModelTagEnglish
        case "Offline":
            return L10n.Settings.ttsModelTagOffline
        case "ANE":
            return L10n.Settings.ttsModelTagANE
        default:
            return tag
        }
    }

    private func selectLocalModel(_ descriptor: LocalTTSModelDescriptor) {
        updateConfig {
            $0.tts.voice = descriptor.voiceID
        }
        localTTSResidency.requestWarm(voiceID: descriptor.voiceID)
    }

    private func testLocalModel(_ descriptor: LocalTTSModelDescriptor) {
        var localConfig = config.tts
        localConfig.engine = localEngineID
        localConfig.remote.enabled = false
        localConfig.voice = descriptor.voiceID
        TTSGeneralPresentationStyle.applyCurrent(to: &localConfig)
        let text = descriptor.language.hasPrefix("zh") ? "本地语音测试。" : "Local voice test."
        Task {
            do {
                _ = try await TTSPlaybackManager.shared.speak(
                    TTSSpeakRequest(
                        text: text,
                        source: "Tsutae",
                        interrupt: true,
                        voice: descriptor.voiceID,
                        rate: localConfig.rate,
                        presentationStyle: localConfig.presentationStyle
                    ),
                    config: localConfig
                )
                await MainActor.run {
                    localTTSResidency.refreshReadyState()
                    playbackSnapshot = TTSPlaybackManager.shared.snapshot()
                }
            } catch {
                await MainActor.run {
                    previewStatusText = error.localizedDescription
                    playbackSnapshot = TTSPlaybackManager.shared.snapshot()
                }
            }
        }
    }

    private func canDeleteLocalModel(_ descriptor: LocalTTSModelDescriptor) -> Bool {
        LocalTTSModelCatalog.isCached(id: descriptor.id)
            && localTTSResidency.warmingVoiceID != descriptor.voiceID
    }

    private func promptDeleteLocalModel(_ descriptor: LocalTTSModelDescriptor) {
        localModelDialog = .init(kind: .confirmDelete(descriptor))
    }

    private func confirmDeleteLocalModel(_ descriptor: LocalTTSModelDescriptor) async {
        do {
            try await LocalTTSModelCatalog.delete(id: descriptor.id)
            await MainActor.run {
                if selectedLocalModel.id == descriptor.id,
                   let replacement = replacementLocalModel(afterDeleting: descriptor.id) {
                    updateConfig {
                        $0.tts.voice = replacement.voiceID
                    }
                }
                localTTSResidency.refreshReadyState()
                playbackSnapshot = TTSPlaybackManager.shared.snapshot()
            }
        } catch {
            await MainActor.run {
                localModelDialog = .init(kind: .error(error.localizedDescription))
            }
        }
    }

    private func replacementLocalModel(afterDeleting modelID: String) -> LocalTTSModelDescriptor? {
        if let cached = LocalTTSModelCatalog.all.first(where: { $0.id != modelID && LocalTTSModelCatalog.isCached(id: $0.id) }) {
            return cached
        }
        if let recommended = LocalTTSModelCatalog.all.first(where: { $0.id != modelID && $0.isRecommended }) {
            return recommended
        }
        return LocalTTSModelCatalog.all.first(where: { $0.id != modelID })
    }

    private func deleteAlertTitle(for descriptor: LocalTTSModelDescriptor) -> String {
        selectedLocalModel.id == descriptor.id ? L10n.Settings.sttDeleteCurrentTitle : L10n.Settings.sttDeleteDownloadedTitle
    }

    private func deleteAlertPrimaryActionTitle(for descriptor: LocalTTSModelDescriptor) -> String {
        selectedLocalModel.id == descriptor.id ? L10n.Settings.sttDeleteAndSwitchAction : L10n.Settings.sttDeleteAction
    }

    private func deleteAlertMessage(for descriptor: LocalTTSModelDescriptor) -> String {
        if selectedLocalModel.id == descriptor.id {
            let replacement = replacementLocalModel(afterDeleting: descriptor.id)?.displayName ?? L10n.Settings.ttsVoiceAutomatic
            return L10n.Settings.sttDeleteCurrentMessage(modelName: descriptor.displayName, replacementName: replacement)
        }
        return L10n.Settings.sttDeleteDownloadedMessage(descriptor.displayName)
    }

    private func saveRemoteSettings() {
        let trimmedAPIKey = remoteDraftAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        updateConfig {
            $0.tts.remote.enabled = true
            $0.tts.remote.baseURL = remoteDraftBaseURL.nilIfBlank
            $0.tts.remote.model = remoteDraftModel.nilIfBlank
            $0.tts.remote.requestStyle = Config.TTSRemoteRequestStyle(rawValue: remoteDraftRequestStyle) ?? .audioSpeech
            $0.tts.remote.instructions = remoteDraftInstructions.nilIfBlank
            $0.tts.remote.voice = remoteDraftVoice.nilIfBlank
        }
        if trimmedAPIKey.isEmpty == false {
            let ref = config.tts.remote.apiKeyRef ?? "tsutae.remote_tts"
            do {
                try SecretsManager.set(trimmedAPIKey, for: ref)
                updateConfig { $0.tts.remote.apiKeyRef = ref }
                remoteDraftAPIKey = ""
                isRemoteAPIKeyRevealed = false
            } catch {
                remoteCheckState = .failed(error.localizedDescription)
                return
            }
        }
        remoteCheckState = .saved
    }

    private func triggerPreview() {
        var previewConfig = config.tts
        TTSGeneralPresentationStyle.applyCurrent(to: &previewConfig)
        let previewVoice = currentPlaybackVoiceID
        let previewRate = previewConfig.rate
        let previewPresentationStyle = previewConfig.presentationStyle
        let previewTextValue = previewText
        Task {
            do {
                try await preflightRemoteKeychainAccessIfNeeded(config: previewConfig)
                _ = try await TTSPlaybackManager.shared.speak(
                    TTSSpeakRequest(
                        text: previewTextValue,
                        source: "Tsutae",
                        interrupt: true,
                        voice: previewVoice,
                        rate: previewRate,
                        presentationStyle: previewPresentationStyle
                    ),
                    config: previewConfig
                )
            } catch {
                previewStatusText = error.localizedDescription
                playbackSnapshot = TTSPlaybackManager.shared.snapshot()
            }
        }
    }

    private func preflightRemoteKeychainAccessIfNeeded(config: Config.TTSConfig) async throws {
        guard config.engine == remoteEngineID, let ref = config.remote.apiKeyRef?.nilIfBlank else {
            return
        }
        do {
            _ = try await Task.detached(priority: .userInitiated) {
                try SecretsManager.get(ref)
            }.value
            await MainActor.run {
                SettingsWindowCoordinator.shared.openSettings(tab: nil)
            }
        } catch {
            await MainActor.run {
                SettingsWindowCoordinator.shared.openSettings(tab: nil)
            }
            throw error
        }
    }

    private func exportPreviewWAV() {
        let trimmedPreview = previewText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedPreview.isEmpty == false else {
            previewStatusText = TTSPlaybackError.emptyText.localizedDescription
            return
        }

        previewStatusText = L10n.Settings.ttsPreviewSynthesizingStatus
        isExportingPreview = true
        exportPayload = nil
        exportTask?.cancel()
        let draftAPIKey = remoteDraftAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let storedAPIKeyRef = config.tts.remote.apiKeyRef
        let effective = effectiveRemoteConfig()
        let isLocalExport = isLocalSelected
        let localVoiceID = config.tts.voice
        let localRate = config.tts.rate
        exportTask = Task.detached(priority: .userInitiated) {
            do {
                let audio: AudioData
                if isLocalExport {
                    audio = try await FluidAudioLocalTTSEngine.shared.synthesize(
                        trimmedPreview,
                        voiceID: localVoiceID,
                        rate: localRate
                    )
                } else {
                    guard effective.remote.baseURL?.nilIfBlank != nil, effective.remote.model?.nilIfBlank != nil else {
                        throw OpenAICompatibleRemoteTTSError.invalidConfiguration
                    }
                    let apiKey: String?
                    if draftAPIKey.isEmpty == false {
                        apiKey = draftAPIKey
                    } else if let storedAPIKeyRef {
                        do {
                            apiKey = try SecretsManager.get(storedAPIKeyRef)
                            await MainActor.run {
                                SettingsWindowCoordinator.shared.openSettings(tab: nil)
                            }
                        } catch {
                            await MainActor.run {
                                SettingsWindowCoordinator.shared.openSettings(tab: nil)
                            }
                            throw error
                        }
                    } else {
                        apiKey = nil
                    }
                    audio = try await OpenAICompatibleRemoteTTSEngine.shared.synthesize(
                        trimmedPreview,
                        voiceID: effective.remote.voice,
                        instructions: effective.remote.instructions,
                        config: effective,
                        apiKeyOverride: apiKey
                    )
                }
                guard Task.isCancelled == false else { return }
                await MainActor.run {
                    exportPayload = TTSExportPayload(data: audio.samples)
                    previewStatusText = L10n.Settings.ttsPreviewChooseLocationStatus
                }
            } catch is CancellationError {
                await MainActor.run {
                    isExportingPreview = false
                    previewStatusText = L10n.Settings.ttsStatusIdle
                }
            } catch {
                await MainActor.run {
                    isExportingPreview = false
                    previewStatusText = error.localizedDescription
                }
            }
        }
    }

    private func cancelPreviewExport() {
        exportTask?.cancel()
        exportTask = nil
        exportPayload = nil
        isExportingPreview = false
        previewStatusText = L10n.Settings.ttsStatusIdle
    }

    private func updateConfig(_ mutate: (inout Config) -> Void) {
        var updated = config
        mutate(&updated)
        config = updated
        do {
            try ConfigLoader.save(updated)
            NotificationCenter.default.post(name: .tsutaeConfigDidChange, object: nil, userInfo: ["config": updated])
            LocalTTSResidencyCoordinator.shared.requestApply(config: updated)
        } catch {
            config = (try? ConfigLoader.load()) ?? config
        }
    }
}

private enum TTSLocalModelPresentationState {
    case notDownloaded
    case downloading
    case downloaded
    case warming
    case ready
}

private struct TTSLocalModelCard: View {
    let descriptor: LocalTTSModelDescriptor
    let isSelected: Bool
    let isCached: Bool
    let isReady: Bool
    let isWarming: Bool
    let downloadProgress: Double?
    let onUse: () -> Void
    let onPreload: () -> Void
    let onTest: () -> Void
    let onDelete: (() -> Void)?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsTokens.Spacing.card) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(descriptor.displayName)
                        .font(.system(size: 20, weight: .semibold))
                    Text(localizedSummary)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(colorScheme == .dark ? DS.color.mutedDark : DS.color.muted)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 88, alignment: .topLeading)

                ModelStateBadge(title: badgeTitle, tone: badgeTone, icon: badgeIcon)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    SettingsMetricPill(title: descriptor.runtime)
                    SettingsMetricPill(title: descriptor.language)
                    SettingsMetricPill(title: descriptor.memory)
                }

                FlowLayout(spacing: 8, lineSpacing: 8) {
                    if descriptor.isRecommended {
                        SettingsFeatureTag(title: L10n.Settings.sttModelTopPick, tone: .accent)
                    }
                    ForEach(descriptor.tags, id: \.self) { tag in
                        SettingsFeatureTag(title: localizedTag(tag), tone: .plain)
                    }
                }
            }

            Spacer(minLength: 0)

            Divider()
                .overlay(colorScheme == .dark ? Color.white.opacity(0.08) : DS.color.borderSoft.opacity(0.56))

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    Text(statusText)
                        .font(DS.font.mono(size: 11, weight: .regular))
                        .foregroundStyle(colorScheme == .dark ? DS.color.mutedDark : DS.color.muted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
                        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                    Spacer(minLength: 12)
                    actionView
                        .fixedSize(horizontal: true, vertical: false)
                }

                if case .downloading = presentationState {
                    STTInlineDownloadProgress(progress: downloadProgress ?? 0)
                }
            }
        }
        .padding(SettingsTokens.Padding.localModelCard)
        .frame(maxWidth: .infinity, minHeight: 244, alignment: .leading)
        .background(cardBackground)
        .overlay(cardBorder)
        .shadow(color: cardShadowColor, radius: 18, x: 0, y: 10)
    }

    private var localizedSummary: String {
        switch descriptor.id {
        case "kokoro-ane-mandarin":
            return L10n.Settings.ttsModelSummaryKokoroMandarin
        case "kokoro-ane-english":
            return L10n.Settings.ttsModelSummaryKokoroEnglish
        default:
            return descriptor.summary
        }
    }

    private func localizedTag(_ tag: String) -> String {
        switch tag {
        case "Mandarin":
            return L10n.Settings.ttsModelTagMandarin
        case "English":
            return L10n.Settings.ttsModelTagEnglish
        case "Offline":
            return L10n.Settings.ttsModelTagOffline
        case "ANE":
            return L10n.Settings.ttsModelTagANE
        default:
            return tag
        }
    }

    private var statusText: String {
        switch presentationState {
        case .notDownloaded:
            return L10n.Settings.sttModelStatusNotDownloaded
        case .downloading:
            return L10n.Settings.sttModelStatusPreparingFiles
        case .downloaded:
            return isSelected ? L10n.Settings.ttsModelStatusDefaultLocalVoice : L10n.Settings.ttsModelStatusDownloaded
        case .warming:
            return L10n.Settings.ttsModelStatusWarmingLocal
        case .ready:
            return isSelected ? L10n.Settings.ttsModelStatusActiveReady : L10n.Settings.ttsModelStatusReady
        }
    }

    private var badgeTitle: String {
        if isWarming { return L10n.Settings.sttModelBadgeWarming }
        if isSelected { return L10n.Settings.sttModelBadgeUsing }
        switch presentationState {
        case .notDownloaded:
            return L10n.Settings.sttModelBadgeAvailable
        case .downloading:
            return L10n.Settings.sttModelBadgeDownloading
        case .downloaded, .ready:
            return L10n.Settings.sttModelBadgeDownloaded
        case .warming:
            return L10n.Settings.sttModelBadgeWarming
        }
    }

    private var badgeTone: ServerStatusCapsule.Tone {
        if isWarming || isSelected { return .active }
        switch presentationState {
        case .downloading, .warming:
            return .active
        case .downloaded, .ready:
            return .soft
        case .notDownloaded:
            return .neutral
        }
    }

    private var badgeIcon: String {
        if isWarming { return "clock.fill" }
        if isSelected { return "checkmark.circle.fill" }
        switch presentationState {
        case .notDownloaded:
            return "arrow.down.circle"
        case .downloading:
            return "arrow.down.circle.fill"
        case .downloaded, .ready:
            return "checkmark.circle"
        case .warming:
            return "clock.fill"
        }
    }

    private var presentationState: TTSLocalModelPresentationState {
        if isWarming {
            return isCached ? .warming : .downloading
        }
        if isReady {
            return .ready
        }
        if isCached {
            return .downloaded
        }
        return .notDownloaded
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(
                isSelected
                    ? (colorScheme == .dark ? DS.color.accentDark.opacity(0.18) : Color.white.opacity(0.97))
                    : (colorScheme == .dark ? DS.color.surface2Dark.opacity(0.9) : Color.white.opacity(0.95))
            )
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(cardBorderColor, lineWidth: isSelected ? 2 : 1.2)
    }

    private var cardBorderColor: Color {
        if isSelected {
            return colorScheme == .dark ? DS.color.accentDark.opacity(0.72) : DS.color.accent.opacity(0.52)
        }
        if isWarming {
            return colorScheme == .dark ? DS.color.accentDark.opacity(0.46) : DS.color.accent.opacity(0.34)
        }
        return colorScheme == .dark ? Color.white.opacity(0.13) : DS.color.borderSoft.opacity(0.86)
    }

    private var cardShadowColor: Color {
        isSelected
            ? (colorScheme == .dark ? DS.color.accentDark.opacity(0.14) : DS.shadow.main)
            : (colorScheme == .dark ? Color.black.opacity(0.14) : DS.shadow.soft)
    }

    @ViewBuilder
    private var actionView: some View {
        if isSelected && (presentationState == .downloaded || presentationState == .ready) {
            HStack(spacing: 8) {
                if let onDelete {
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(SettingsDangerIconButtonStyle())
                    .controlSize(.small)
                }

                Button(L10n.Settings.ttsModelActionTest, action: onTest)
                    .buttonStyle(SettingsAccentButtonStyle())
                    .controlSize(.small)
                    .frame(minWidth: 116)
            }
        } else if presentationState == .downloaded || presentationState == .ready {
            HStack(spacing: 8) {
                if let onDelete {
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(SettingsDangerIconButtonStyle())
                    .controlSize(.small)
                }

                Button(L10n.Settings.sttModelActionSetDefault, action: onUse)
                    .buttonStyle(SettingsAccentButtonStyle())
                    .controlSize(.small)
                    .frame(minWidth: 116)
            }
        } else if isWarming {
            Button(isCached ? L10n.Settings.ttsModelActionWarming : L10n.Settings.sttModelActionDownloading, action: onPreload)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(minWidth: 116)
                .disabled(true)
        } else {
            Button(L10n.Settings.sttModelActionDownload, action: onPreload)
                .buttonStyle(SettingsAccentButtonStyle())
                .controlSize(.small)
                .frame(minWidth: 116)
        }
    }
}

private struct TTSRateControl: View {
    @Binding var rate: Double
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            Slider(value: $rate, in: 0.5...2.0, step: 0.1)
                .tint(DS.color.accent)
                .frame(width: 190)

            Text(String(format: "%.1fx", rate))
                .font(DS.font.mono(size: 12, weight: .medium))
                .foregroundStyle(colorScheme == .dark ? DS.color.foregroundDark.opacity(0.84) : DS.color.foreground.opacity(0.76))
                .frame(width: 46, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(width: SettingsTokens.Size.remoteFieldWidth, height: SettingsTokens.Size.controlHeight, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(colorScheme == .dark ? DS.color.surface2Dark.opacity(0.92) : Color.white.opacity(0.88))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(colorScheme == .dark ? DS.color.borderDarkSoft.opacity(0.42) : DS.color.borderSoft.opacity(0.62), lineWidth: 1)
                )
        )
    }
}

private struct TTSExportSavePanelPresenter: NSViewRepresentable {
    @Binding var payload: TTSExportPayload?
    @Binding var statusText: String?
    @Binding var isExporting: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.parent = self
        guard let payload else { return }
        context.coordinator.presentIfNeeded(payload: payload, from: nsView)
    }

    final class Coordinator: NSObject {
        var parent: TTSExportSavePanelPresenter
        private var presentingPayloadID: UUID?
        private var retainedPanel: NSSavePanel?

        init(parent: TTSExportSavePanelPresenter) {
            self.parent = parent
        }

        func presentIfNeeded(payload: TTSExportPayload, from view: NSView) {
            guard presentingPayloadID != payload.id else { return }
            presentingPayloadID = payload.id

            DispatchQueue.main.async { [weak self, weak view] in
                guard let self else { return }
                let panel = NSSavePanel()
                panel.title = L10n.Settings.ttsPreviewExportButton
                panel.prompt = L10n.Settings.ttsPreviewExportButton
                panel.nameFieldStringValue = "tsutae-tts.wav"
                panel.canCreateDirectories = true
                panel.allowedContentTypes = [UTType(filenameExtension: "wav") ?? .audio]
                panel.isExtensionHidden = false
                self.retainedPanel = panel

                let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
                    guard let self else { return }
                    defer {
                        self.retainedPanel = nil
                        self.presentingPayloadID = nil
                    }

                    guard response == .OK, let url = panel.url else {
                        self.parent.payload = nil
                        self.parent.isExporting = false
                        self.parent.statusText = L10n.Settings.ttsStatusIdle
                        return
                    }

                    do {
                        try payload.data.write(to: url, options: .atomic)
                        self.parent.payload = nil
                        self.parent.isExporting = false
                        self.parent.statusText = L10n.Settings.ttsPreviewExportedStatus
                    } catch {
                        self.parent.payload = nil
                        self.parent.isExporting = false
                        self.parent.statusText = error.localizedDescription
                    }
                }

                NSApp.activate(ignoringOtherApps: true)
                if let window = view?.window {
                    panel.beginSheetModal(for: window, completionHandler: completion)
                } else {
                    panel.begin(completionHandler: completion)
                }
            }
        }
    }
}
