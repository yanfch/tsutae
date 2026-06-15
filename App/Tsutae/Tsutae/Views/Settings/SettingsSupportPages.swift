import AppKit
import AVFoundation
import Speech
import SwiftUI
import TsutaeCore
import UniformTypeIdentifiers
import UserNotifications

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

private enum TTSSettingsScreen {
    case overview
    case localModels
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

                    SettingsToggleRow(
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
                    SettingsToggleRow(
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
                                .buttonStyle(SettingsIconButtonStyle())
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
                SettingsToggleRow(
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
                    ForEach(LocalTTSModelCatalog.all) { descriptor in
                        TTSLocalModelCard(
                            descriptor: descriptor,
                            isSelected: selectedLocalModel.voiceID == descriptor.voiceID,
                            isCached: LocalTTSModelCatalog.isCached(id: descriptor.id),
                            isReady: localTTSResidency.readyVoiceIDs.contains(descriptor.voiceID),
                            isWarming: localTTSResidency.warmingVoiceID == descriptor.voiceID,
                            onUse: { selectLocalModel(descriptor) },
                            onPreload: { localTTSResidency.requestWarm(voiceID: descriptor.voiceID) },
                            onTest: { testLocalModel(descriptor) }
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
        let base = playbackSnapshot.state == .idle ? L10n.Settings.ttsStatusIdle : L10n.Settings.ttsStatusSpeaking
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
    let onUse: () -> Void
    let onPreload: () -> Void
    let onTest: () -> Void
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
            Button(L10n.Settings.ttsModelActionTest, action: onTest)
                .buttonStyle(SettingsAccentButtonStyle())
                .controlSize(.small)
                .frame(minWidth: 116)
        } else if presentationState == .downloaded || presentationState == .ready {
            Button(L10n.Settings.sttModelActionSetDefault, action: onUse)
                .buttonStyle(SettingsAccentButtonStyle())
                .controlSize(.small)
                .frame(minWidth: 116)
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

private enum ServerHealthProbeState {
    case idle
    case checking
    case online(HealthStatus)
    case offline(String)

    var badgeTitle: String {
        switch self {
        case .idle:
            return L10n.Settings.serverStatusUnknown
        case .checking:
            return L10n.Settings.serverStatusChecking
        case .online:
            return L10n.Settings.serverStatusOnline
        case .offline:
            return L10n.Settings.serverStatusOffline
        }
    }

    var badgeTone: ServerStatusCapsule.Tone {
        switch self {
        case .idle, .checking:
            return .soft
        case .online:
            return .active
        case .offline:
            return .neutral
        }
    }

    var isChecking: Bool {
        if case .checking = self { return true }
        return false
    }
}

private enum ServerHookTarget {
    static let defaultID = "default"
}

private struct ServerGeneratedTokenRow: View {
    let clientName: String
    let token: String
    let copy: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(clientName.isEmpty ? L10n.Settings.serverClientTokenLabel : clientName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(token)
                    .font(DS.font.mono(size: 12, weight: .regular))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .foregroundStyle(colorScheme == .dark ? DS.color.foregroundDark : DS.color.foreground)
            }

            Spacer(minLength: 12)

            Button {
                copy()
            } label: {
                Label(L10n.Settings.serverClientCopyTokenButton, systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(colorScheme == .dark ? DS.color.surface2Dark.opacity(0.72) : Color.white.opacity(0.62))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(colorScheme == .dark ? DS.color.accentDark.opacity(0.28) : DS.color.accent.opacity(0.18), lineWidth: 1)
                )
        )
    }
}

struct ServerSettingsPage: View {
    @State private var config = (try? ConfigLoader.load()) ?? .default
    @State private var bindDraft = ""
    @State private var portDraft = ""
    @State private var statusText: String?
    @State private var copiedEndpointID: String?
    @State private var healthState: ServerHealthProbeState = .idle
    @State private var isRuntimeExpanded = false
    @State private var hookEventRaw = Config.ServerHookEvent.onTranscribed.rawValue
    @State private var hookTargetID = ServerHookTarget.defaultID
    @State private var hookEnabledDraft = false
    @State private var hookURLDraft = ""
    @State private var hookTokenRefDraft = ""
    @State private var hookTimeoutDraft = "5000"
    @State private var hookStatusText: String?
    @State private var isTestingHook = false
    @State private var isAdvancedScopesExpanded = false
    @State private var newClientName = ""
    @State private var activeClientID: String?
    @State private var generatedClientToken: String?
    @State private var generatedClientTokenClientID: String?
    @State private var generatedClientTokenClientName: String?
    @State private var clientStatusText: String?
    private let hookController = DefaultAppController()

    var body: some View {
        Group {
            if let activeClient {
                serverClientDetailPage(activeClient)
            } else {
                serverMainPage
            }
        }
        .onAppear {
            reloadConfig()
        }
        .task {
            await refreshHealth()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tsutaeConfigDidChange)) { notification in
            if let config = notification.userInfo?["config"] as? Config {
                apply(config)
            } else {
                reloadConfig()
            }
        }
        .onChange(of: hookEventRaw) { _, _ in
            loadHookDraft(from: config)
        }
        .onChange(of: hookTargetID) { _, _ in
            loadHookDraft(from: config)
            clearGeneratedTokenIfNeeded()
        }
    }

    private var serverMainPage: some View {
        VStack(alignment: .leading, spacing: SettingsTokens.Spacing.section) {
            serverRuntimeCard
            serverClientsCard

            SettingsTwoColumnGrid {
                SettingsDashboardCard(title: L10n.Settings.serverCapabilitiesTitle, subtitle: L10n.Settings.serverCapabilitiesSubtitle) {
                    SettingsKeyValueList(rows: [
                        ("/v1/audio/transcriptions", L10n.Settings.serverCapabilityAvailable),
                        ("/v1/audio/speech", L10n.Settings.serverCapabilityAvailable),
                        ("/v1/tts/voices", L10n.Settings.serverCapabilityAvailable),
                        ("/v1/speak", L10n.Settings.serverCapabilityAvailable),
                        ("/v1/notify", L10n.Settings.serverCapabilityAvailable),
                        ("/v1/stop", L10n.Settings.serverCapabilityAvailable),
                        ("/v1/listen", L10n.Settings.valuePlanned),
                        (L10n.Settings.labelHooks, hooksCapabilityValue)
                    ])
                }

                SettingsDashboardCard(title: L10n.Settings.serverHealthTitle, subtitle: L10n.Settings.serverHealthSubtitle) {
                    SettingsMetricStack(items: healthRows, accent: healthAccent)
                }
            }

            serverAPIEndpointsCard
        }
    }

    private var serverRuntimeCard: some View {
        SettingsDashboardCard(title: L10n.Settings.serverRuntimeTitle, subtitle: L10n.Settings.serverRuntimeSubtitle) {
            VStack(alignment: .leading, spacing: SettingsTokens.Spacing.content) {
                HStack(spacing: 8) {
                    ServerStatusCapsule(title: healthState.badgeTitle, tone: healthState.badgeTone)
                    ServerStatusCapsule(title: baseURLString, tone: .soft)
                    ServerStatusCapsule(
                        title: config.server.autoStart ? L10n.Settings.toggleOn : L10n.Settings.toggleOff,
                        tone: config.server.autoStart ? .active : .neutral
                    )
                    ServerStatusCapsule(
                        title: config.server.requireToken ? L10n.Settings.serverRequireTokenTitle : L10n.Settings.valueLocalhost,
                        tone: config.server.requireToken ? .active : .soft
                    )
                    Spacer(minLength: 0)

                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                            isRuntimeExpanded.toggle()
                        }
                    } label: {
                        Label(
                            isRuntimeExpanded ? L10n.Settings.serverRuntimeCollapseButton : L10n.Settings.serverRuntimeConfigureButton,
                            systemImage: isRuntimeExpanded ? "chevron.up" : "slider.horizontal.3"
                        )
                    }
                    .buttonStyle(.bordered)
                }

                if isRuntimeExpanded {
                    SettingsToggleRow(
                        title: L10n.Settings.serverAutostartTitle,
                        subtitle: L10n.Settings.serverAutostartSubtitle,
                        isOn: autoStartBinding,
                        badgeTitle: config.server.autoStart ? L10n.Settings.toggleOn : L10n.Settings.toggleOff,
                        badgeTone: config.server.autoStart ? .active : .neutral
                    )

                    SettingsSection(title: L10n.Settings.serverNotificationsTitle) {
                        SettingsFormRow(
                            label: L10n.Settings.serverNotificationSoundLabel,
                            helpText: L10n.Settings.serverNotificationSoundHelp
                        ) {
                            SettingsChipSelector(
                                selection: notificationSoundPolicyBinding,
                                options: [
                                    (Config.NotificationSoundPolicy.important.rawValue, L10n.Settings.serverNotificationSoundImportant),
                                    (Config.NotificationSoundPolicy.all.rawValue, L10n.Settings.serverNotificationSoundAll),
                                    (Config.NotificationSoundPolicy.silent.rawValue, L10n.Settings.serverNotificationSoundSilent)
                                ]
                            )
                        }
                    }

                    SettingsSection(title: L10n.Settings.serverAccessTitle) {
                        SettingsFormRow(label: L10n.Settings.serverBindLabel) {
                            SettingsInlineTextField(text: $bindDraft, placeholder: "127.0.0.1", width: 190)
                        }
                        SettingsDivider()
                        SettingsFormRow(label: L10n.Settings.serverPortLabel) {
                            SettingsInlineTextField(text: $portDraft, placeholder: "1338", width: 110)
                        }
                    }

                    SettingsToggleRow(
                        title: L10n.Settings.serverRequireTokenTitle,
                        subtitle: L10n.Settings.serverRequireTokenSubtitle,
                        isOn: requireTokenBinding,
                        badgeTitle: config.server.requireToken ? L10n.Settings.toggleOn : L10n.Settings.toggleOff,
                        badgeTone: config.server.requireToken ? .active : .neutral
                    )

                    HStack(spacing: 10) {
                        Button {
                            saveDraft()
                        } label: {
                            Label(L10n.Settings.serverSaveButton, systemImage: "checkmark")
                        }
                        .buttonStyle(SettingsAccentButtonStyle())

                        Button {
                            Task { await refreshHealth() }
                        } label: {
                            Label(healthState.isChecking ? L10n.Settings.serverStatusChecking : L10n.Settings.serverCheckButton, systemImage: "waveform.path.ecg")
                        }
                        .buttonStyle(.bordered)
                        .disabled(healthState.isChecking)

                        Button {
                            copyEndpoint(id: "base", title: L10n.Settings.labelBaseURL, path: "")
                        } label: {
                            Label(L10n.Settings.serverCopyButton, systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)

                        Spacer(minLength: 0)
                    }

                    if let statusText {
                        Text(statusText)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var serverClientsCard: some View {
        SettingsDashboardCard(title: L10n.Settings.serverClientsTitle, subtitle: L10n.Settings.serverClientsSubtitle) {
            VStack(alignment: .leading, spacing: SettingsTokens.Spacing.content) {
                HStack(spacing: 8) {
                    ServerStatusCapsule(title: L10n.Settings.serverClientCount(config.server.clients.count), tone: config.server.clients.isEmpty ? .neutral : .active)
                    ServerStatusCapsule(title: config.server.requireToken ? L10n.Settings.serverRequireTokenTitle : L10n.Settings.valueLocalhost, tone: config.server.requireToken ? .active : .soft)
                    Spacer(minLength: 0)
                }

                SettingsSection(title: L10n.Settings.serverClientsTitle) {
                    SettingsFormRow(label: L10n.Settings.serverClientNewNameLabel) {
                        SettingsInlineTextField(
                            text: $newClientName,
                            placeholder: L10n.Settings.serverClientNamePlaceholder,
                            width: SettingsTokens.Size.remoteFieldWidth
                        )
                    }
                }

                HStack {
                    Button {
                        createClient()
                    } label: {
                        Label(L10n.Settings.serverClientCreateButton, systemImage: "plus")
                    }
                    .buttonStyle(SettingsAccentButtonStyle())
                    Spacer(minLength: 0)
                }

                if config.server.clients.isEmpty {
                    Text(L10n.Settings.serverClientsSubtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(spacing: 10) {
                        ForEach(config.server.clients) { client in
                            Button {
                                openClientDetail(client)
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(client.name)
                                            .font(.system(size: 13, weight: .semibold))
                                        Text(client.createdAt ?? client.id)
                                            .font(DS.font.mono(size: 11, weight: .regular))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }

                                    Spacer(minLength: 12)

                                    ServerStatusCapsule(
                                        title: client.enabled ? L10n.Settings.serverClientStatusEnabled : L10n.Settings.serverClientStatusDisabled,
                                        tone: client.enabled ? .success : .neutral
                                    )
                                    ServerStatusCapsule(title: L10n.Settings.serverClientScopeCount(client.scopes.count), tone: .soft)
                                    ServerStatusCapsule(title: clientHookSummary(client), tone: clientHookEnabled(client) ? .active : .neutral)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color.primary.opacity(0.035))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .strokeBorder(Color.secondary.opacity(0.16), lineWidth: 1)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if let clientStatusText {
                    Text(clientStatusText)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private func serverClientDetailPage(_ client: Config.ServerClientConfig) -> some View {
        VStack(alignment: .leading, spacing: SettingsTokens.Spacing.section) {
            Button {
                closeClientDetail()
            } label: {
                Label(L10n.Settings.serverClientBackButton, systemImage: "chevron.left")
            }
            .buttonStyle(.bordered)

            SettingsDashboardCard(title: client.name, subtitle: L10n.Settings.serverClientDetailSubtitle) {
                VStack(alignment: .leading, spacing: SettingsTokens.Spacing.content) {
                    HStack(spacing: 8) {
                        ServerStatusCapsule(
                            title: client.enabled ? L10n.Settings.serverClientStatusEnabled : L10n.Settings.serverClientStatusDisabled,
                            tone: client.enabled ? .success : .neutral
                        )
                        ServerStatusCapsule(title: L10n.Settings.serverClientScopeCount(client.scopes.count), tone: .soft)
                        ServerStatusCapsule(title: clientHookSummary(client), tone: clientHookEnabled(client) ? .active : .neutral)
                        Spacer(minLength: 0)
                    }

                    HStack(spacing: 10) {
                        Button {
                            regenerateSelectedClientToken()
                        } label: {
                            Label(L10n.Settings.serverClientRegenerateTokenButton, systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(SettingsAccentButtonStyle())

                        Button {
                            setSelectedClientEnabled(!client.enabled)
                        } label: {
                            Label(
                                client.enabled ? L10n.Settings.serverClientDisableButton : L10n.Settings.serverClientEnableButton,
                                systemImage: client.enabled ? "pause.circle" : "play.circle"
                            )
                        }
                        .buttonStyle(.bordered)

                        Spacer(minLength: 0)
                    }

                    if let generatedClientToken, generatedClientTokenClientID == client.id {
                        ServerGeneratedTokenRow(
                            clientName: generatedClientTokenClientName ?? client.name,
                            token: generatedClientToken
                        ) {
                            copyGeneratedClientToken()
                        }
                    }

                    SettingsKeyValueList(rows: [
                        (L10n.Settings.serverClientSelectLabel, client.name),
                        (L10n.Settings.serverClientTokenLabel, L10n.Settings.valueManaged),
                        (L10n.Settings.labelHooks, clientHookSummary(client)),
                        (L10n.Settings.labelStatus, client.enabled ? L10n.Settings.serverClientStatusEnabled : L10n.Settings.serverClientStatusDisabled),
                        (L10n.Settings.labelCallbacks, L10n.Settings.serverClientScopeCount(client.scopes.count))
                    ])

                    if let clientStatusText {
                        Text(clientStatusText)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            serverClientPermissionsCard(client)
            serverHooksCard
        }
        .onAppear {
            if hookTargetID != client.id {
                hookTargetID = client.id
            }
        }
    }

    private func serverClientPermissionsCard(_ client: Config.ServerClientConfig) -> some View {
        SettingsDashboardCard(title: L10n.Settings.serverClientPermissionsTitle, subtitle: L10n.Settings.serverClientPermissionsSubtitle) {
            VStack(alignment: .leading, spacing: SettingsTokens.Spacing.content) {
                clientScopeGrid(primaryClientScopes, client: client)

                SettingsDivider()

                HStack(spacing: 10) {
                    Text(L10n.Settings.serverClientAdvancedScopesTitle)
                        .font(.system(size: 13, weight: .medium))
                    ServerStatusCapsule(
                        title: L10n.Settings.serverClientScopeCount(enabledScopeCount(in: advancedClientScopes, client: client)),
                        tone: enabledScopeCount(in: advancedClientScopes, client: client) > 0 ? .active : .neutral
                    )
                    Spacer(minLength: 0)
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                            isAdvancedScopesExpanded.toggle()
                        }
                    } label: {
                        Label(
                            isAdvancedScopesExpanded ? L10n.Settings.serverClientHideAdvancedScopes : L10n.Settings.serverClientShowAdvancedScopes,
                            systemImage: isAdvancedScopesExpanded ? "chevron.up" : "chevron.down"
                        )
                    }
                    .buttonStyle(.bordered)
                }

                if isAdvancedScopesExpanded {
                    clientScopeGrid(advancedClientScopes, client: client)
                }
            }
        }
    }

    private func clientScopeGrid(_ scopes: [Config.ServerClientScope], client: Config.ServerClientConfig) -> some View {
        let columns = [
            GridItem(.flexible(minimum: 220), spacing: 10, alignment: .top),
            GridItem(.flexible(minimum: 220), spacing: 10, alignment: .top)
        ]

        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(scopes, id: \.rawValue) { scope in
                SettingsToggleRow(
                    title: clientScopeTitle(scope),
                    subtitle: clientScopeDescription(scope),
                    isOn: clientScopeBinding(scope, clientID: client.id),
                    badgeTitle: client.scopes.contains(scope) ? L10n.Settings.toggleOn : L10n.Settings.toggleOff,
                    badgeTone: client.scopes.contains(scope) ? .active : .neutral
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.primary.opacity(0.035))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.secondary.opacity(0.16), lineWidth: 1)
                        )
                )
            }
        }
    }

    private var primaryClientScopes: [Config.ServerClientScope] {
        [.state, .models, .transcribe, .audioSpeech, .speak, .notify, .stop]
    }

    private var advancedClientScopes: [Config.ServerClientScope] {
        [.listen, .recipes, .secrets, .configRead]
    }

    private func enabledScopeCount(in scopes: [Config.ServerClientScope], client: Config.ServerClientConfig) -> Int {
        scopes.filter { client.scopes.contains($0) }.count
    }

    private var serverHooksCard: some View {
        SettingsDashboardCard(title: L10n.Settings.serverHooksTitle, subtitle: L10n.Settings.serverHooksSubtitle) {
            VStack(alignment: .leading, spacing: SettingsTokens.Spacing.content) {
                HStack(spacing: 8) {
                    ServerStatusCapsule(
                        title: L10n.Settings.labelOnTranscribed,
                        tone: selectedHooksConfig.onTranscribed.enabled ? .active : .neutral
                    )
                    ServerStatusCapsule(
                        title: L10n.Settings.labelOnError,
                        tone: selectedHooksConfig.onError.enabled ? .active : .neutral
                    )
                    ServerStatusCapsule(title: L10n.Settings.labelOnSpoken, tone: selectedHooksConfig.onSpoken.enabled ? .active : .neutral)
                    ServerStatusCapsule(title: selectedHookTargetTitle, tone: selectedClient == nil ? .soft : .active)
                    Spacer(minLength: 0)
                }

                Text(L10n.Settings.serverClientHooksNote)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                SettingsSection(title: L10n.Settings.labelCallbacks) {
                    SettingsFormRow(label: L10n.Settings.serverHookEventLabel) {
                        SettingsChipSelector(
                            selection: $hookEventRaw,
                            options: [
                                (Config.ServerHookEvent.onTranscribed.rawValue, L10n.Settings.labelOnTranscribed),
                                (Config.ServerHookEvent.onSpoken.rawValue, L10n.Settings.labelOnSpoken),
                                (Config.ServerHookEvent.onError.rawValue, L10n.Settings.labelOnError)
                            ]
                        )
                    }
                    SettingsDivider()
                    SettingsFormRow(label: L10n.Settings.serverHookEnabledLabel) {
                        HStack(spacing: 10) {
                            ServerStatusCapsule(
                                title: hookEnabledDraft ? L10n.Settings.toggleOn : L10n.Settings.toggleOff,
                                tone: hookEnabledDraft ? .active : .neutral
                            )
                            Toggle("", isOn: $hookEnabledDraft)
                                .labelsHidden()
                                .toggleStyle(SettingsSwitchToggleStyle())
                        }
                    }
                    SettingsDivider()
                    SettingsFormRow(label: L10n.Settings.serverHookURLLabel) {
                        SettingsInlineTextField(
                            text: $hookURLDraft,
                            placeholder: L10n.Settings.serverHookURLPlaceholder,
                            width: SettingsTokens.Size.remoteFieldWidth
                        )
                    }
                    SettingsDivider()
                    SettingsFormRow(label: L10n.Settings.serverHookTokenRefLabel) {
                        SettingsInlineTextField(
                            text: $hookTokenRefDraft,
                            placeholder: L10n.Settings.serverHookTokenRefPlaceholder,
                            width: SettingsTokens.Size.remoteFieldWidth
                        )
                    }
                    SettingsDivider()
                    SettingsFormRow(label: L10n.Settings.serverHookTimeoutLabel) {
                        SettingsInlineTextField(text: $hookTimeoutDraft, placeholder: "5000", width: 120)
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        _ = saveHookDraft(showStatus: true)
                    } label: {
                        Label(L10n.Settings.serverHookSaveButton, systemImage: "checkmark")
                    }
                    .buttonStyle(SettingsAccentButtonStyle())

                    Button {
                        Task { await testSelectedHook() }
                    } label: {
                        Label(
                            isTestingHook ? L10n.Settings.serverHookTestingStatus : L10n.Settings.serverHookTestButton,
                            systemImage: "paperplane"
                        )
                    }
                    .buttonStyle(.bordered)
                    .disabled(isTestingHook || hookEnabledDraft == false || hookURLDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Spacer(minLength: 0)
                }

                if let hookStatusText {
                    Text(hookStatusText)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var serverAPIEndpointsCard: some View {
        SettingsDashboardCard(title: L10n.Settings.serverAPIEndpointsTitle, subtitle: L10n.Settings.serverAPIEndpointsSubtitle) {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(minimum: 280), spacing: 12, alignment: .top),
                    GridItem(.flexible(minimum: 280), spacing: 12, alignment: .top)
                ],
                spacing: 10
            ) {
                ServerEndpointRow(title: L10n.Settings.serverEndpointHealth, path: "/health", isCopied: copiedEndpointID == "health") {
                    copyEndpoint(id: "health", title: L10n.Settings.serverEndpointHealth, path: "/health")
                }
                ServerEndpointRow(title: L10n.Settings.serverEndpointState, path: "/v1/state", isCopied: copiedEndpointID == "state") {
                    copyEndpoint(id: "state", title: L10n.Settings.serverEndpointState, path: "/v1/state")
                }
                ServerEndpointRow(title: L10n.Settings.serverEndpointSTT, path: "/v1/audio/transcriptions", isCopied: copiedEndpointID == "stt") {
                    copyEndpoint(id: "stt", title: L10n.Settings.serverEndpointSTT, path: "/v1/audio/transcriptions")
                }
                ServerEndpointRow(title: L10n.Settings.serverEndpointTTSAudio, path: "/v1/audio/speech", isCopied: copiedEndpointID == "tts-audio") {
                    copyEndpoint(id: "tts-audio", title: L10n.Settings.serverEndpointTTSAudio, path: "/v1/audio/speech")
                }
                ServerEndpointRow(title: L10n.Settings.serverEndpointTTSVoices, path: "/v1/tts/voices", isCopied: copiedEndpointID == "tts-voices") {
                    copyEndpoint(id: "tts-voices", title: L10n.Settings.serverEndpointTTSVoices, path: "/v1/tts/voices")
                }
                ServerEndpointRow(title: L10n.Settings.serverEndpointSpeak, path: "/v1/speak", isCopied: copiedEndpointID == "speak") {
                    copyEndpoint(id: "speak", title: L10n.Settings.serverEndpointSpeak, path: "/v1/speak")
                }
                ServerEndpointRow(title: L10n.Settings.serverEndpointNotify, path: "/v1/notify", isCopied: copiedEndpointID == "notify") {
                    copyEndpoint(id: "notify", title: L10n.Settings.serverEndpointNotify, path: "/v1/notify")
                }
                ServerEndpointRow(title: L10n.Settings.serverEndpointStop, path: "/v1/stop", isCopied: copiedEndpointID == "stop") {
                    copyEndpoint(id: "stop", title: L10n.Settings.serverEndpointStop, path: "/v1/stop")
                }
            }
        }
    }

    private var autoStartBinding: Binding<Bool> {
        Binding(
            get: { config.server.autoStart },
            set: { newValue in
                var updated = config
                updated.server.autoStart = newValue
                persist(updated, status: L10n.Settings.serverSavedRestartRequired)
            }
        )
    }

    private var requireTokenBinding: Binding<Bool> {
        Binding(
            get: { config.server.requireToken },
            set: { newValue in
                var updated = config
                updated.server.requireToken = newValue
                persist(updated, status: L10n.Settings.serverSavedStatus)
            }
        )
    }

    private var notificationSoundPolicyBinding: Binding<String> {
        Binding(
            get: { config.notifications.soundPolicy.rawValue },
            set: { rawValue in
                guard let soundPolicy = Config.NotificationSoundPolicy(rawValue: rawValue) else {
                    return
                }
                var updated = config
                updated.notifications.soundPolicy = soundPolicy
                persist(updated, status: L10n.Settings.serverSavedStatus)
            }
        )
    }

    private var baseURLString: String {
        let bind = bindDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = portDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return "http://\(bind.isEmpty ? config.server.bind : bind):\(port.isEmpty ? String(config.server.port) : port)"
    }

    private var healthRows: [(String, String)] {
        switch healthState {
        case .online(let health):
            return [
                (L10n.Settings.labelStatus, health.status),
                (L10n.Settings.labelVersion, health.version),
                (L10n.Settings.labelSTT, "\(health.engines.stt)"),
                (L10n.Settings.labelTTS, "\(health.engines.tts)"),
                (L10n.Settings.labelVAD, "\(health.engines.vad)")
            ]
        case .offline(let message):
            return [
                (L10n.Settings.labelStatus, L10n.Settings.serverStatusOffline),
                (L10n.Settings.labelLastError, message)
            ]
        case .checking:
            return [
                (L10n.Settings.labelStatus, L10n.Settings.serverStatusChecking),
                (L10n.Settings.labelBaseURL, baseURLString)
            ]
        case .idle:
            return [
                (L10n.Settings.labelStatus, L10n.Settings.serverStatusUnknown),
                (L10n.Settings.labelBaseURL, baseURLString)
            ]
        }
    }

    private var healthAccent: Color {
        switch healthState {
        case .online:
            return DS.color.success
        case .offline:
            return DS.color.warning
        case .checking, .idle:
            return DS.color.accent
        }
    }

    private var selectedHookEvent: Config.ServerHookEvent {
        Config.ServerHookEvent(rawValue: hookEventRaw) ?? .onTranscribed
    }

    private var activeClient: Config.ServerClientConfig? {
        guard let activeClientID else { return nil }
        return config.server.clients.first { $0.id == activeClientID }
    }

    private var selectedClient: Config.ServerClientConfig? {
        guard hookTargetID != ServerHookTarget.defaultID else { return nil }
        return config.server.clients.first { $0.id == hookTargetID }
    }

    private var selectedHooksConfig: Config.ServerHooksConfig {
        selectedClient?.hooks ?? config.server.hooks
    }

    private var selectedHookTargetTitle: String {
        selectedClient?.name ?? L10n.Settings.serverHookDefaultTarget
    }

    private var hookTargetOptions: [SettingsDropdownOption] {
        [SettingsDropdownOption(id: ServerHookTarget.defaultID, title: L10n.Settings.serverHookDefaultTarget)]
            + config.server.clients.map { SettingsDropdownOption(id: $0.id, title: $0.name) }
    }

    private var hooksEnabledCount: Int {
        let globalCount = [
            config.server.hooks.onTranscribed.enabled,
            config.server.hooks.onSpoken.enabled,
            config.server.hooks.onError.enabled
        ].filter { $0 }.count
        let clientCount = config.server.clients.reduce(0) { partial, client in
            partial + [
                client.hooks.onTranscribed.enabled,
                client.hooks.onSpoken.enabled,
                client.hooks.onError.enabled
            ].filter { $0 }.count
        }
        return globalCount + clientCount
    }

    private var hooksCapabilityValue: String {
        hooksEnabledCount > 0 ? L10n.Settings.serverHooksConfiguredCount(hooksEnabledCount) : L10n.Settings.valueConfigurable
    }

    private func reloadConfig() {
        apply((try? ConfigLoader.load()) ?? config)
    }

    private func apply(_ nextConfig: Config) {
        config = nextConfig
        bindDraft = nextConfig.server.bind
        portDraft = String(nextConfig.server.port)
        if let activeClientID,
           nextConfig.server.clients.contains(where: { $0.id == activeClientID }) == false {
            self.activeClientID = nil
        }
        if hookTargetID != ServerHookTarget.defaultID,
           nextConfig.server.clients.contains(where: { $0.id == hookTargetID }) == false {
            hookTargetID = ServerHookTarget.defaultID
        }
        loadHookDraft(from: nextConfig)
    }

    private func saveDraft() {
        let bind = bindDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard bind.isEmpty == false else {
            statusText = L10n.Settings.serverInvalidBind
            return
        }
        guard let port = Int(portDraft.trimmingCharacters(in: .whitespacesAndNewlines)), (1...65_535).contains(port) else {
            statusText = L10n.Settings.serverInvalidPort
            return
        }

        var updated = config
        updated.server.bind = bind
        updated.server.port = port
        persist(updated, status: L10n.Settings.serverSavedRestartRequired)
    }

    private func persist(_ updated: Config, status: String) {
        config = updated
        do {
            try ConfigLoader.save(updated)
            statusText = status
            NotificationCenter.default.post(name: .tsutaeConfigDidChange, object: nil, userInfo: ["config": updated])
        } catch {
            statusText = error.localizedDescription
            reloadConfig()
        }
    }

    private func loadHookDraft(from config: Config) {
        let hooks: Config.ServerHooksConfig
        if let client = selectedClient(in: config) {
            hooks = client.hooks
        } else {
            hooks = config.server.hooks
        }
        let endpoint = hooks.endpoint(for: selectedHookEvent)
        hookEnabledDraft = endpoint.enabled
        hookURLDraft = endpoint.url ?? ""
        hookTokenRefDraft = endpoint.tokenRef ?? ""
        hookTimeoutDraft = String(endpoint.timeoutMs)
    }

    private func saveHookDraft(showStatus: Bool) -> Bool {
        let url = hookURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokenRef = hookTokenRefDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hookEnabledDraft == false || url.isEmpty == false else {
            hookStatusText = L10n.Settings.serverHookInvalidURL
            return false
        }
        guard let timeout = Int(hookTimeoutDraft.trimmingCharacters(in: .whitespacesAndNewlines)), (1_000...120_000).contains(timeout) else {
            hookStatusText = L10n.Settings.serverHookInvalidTimeout
            return false
        }

        let endpoint = Config.ServerHookEndpoint(
            enabled: hookEnabledDraft,
            url: url.isEmpty ? nil : url,
            tokenRef: tokenRef.isEmpty ? nil : tokenRef,
            timeoutMs: timeout
        )

        var updated = config
        if let index = selectedClientIndex(in: updated) {
            switch selectedHookEvent {
            case .onTranscribed:
                updated.server.clients[index].hooks.onTranscribed = endpoint
            case .onSpoken:
                updated.server.clients[index].hooks.onSpoken = endpoint
            case .onError:
                updated.server.clients[index].hooks.onError = endpoint
            }
        } else {
            switch selectedHookEvent {
            case .onTranscribed:
                updated.server.hooks.onTranscribed = endpoint
            case .onSpoken:
                updated.server.hooks.onSpoken = endpoint
            case .onError:
                updated.server.hooks.onError = endpoint
            }
        }

        config = updated
        do {
            try ConfigLoader.save(updated)
            NotificationCenter.default.post(name: .tsutaeConfigDidChange, object: nil, userInfo: ["config": updated])
            if showStatus {
                hookStatusText = L10n.Settings.serverHookSavedStatus
            }
            return true
        } catch {
            hookStatusText = error.localizedDescription
            reloadConfig()
            return false
        }
    }

    private func openClientDetail(_ client: Config.ServerClientConfig) {
        activeClientID = client.id
        hookTargetID = client.id
        clientStatusText = nil
        hookStatusText = nil
        clearGeneratedTokenIfNeeded()
        loadHookDraft(from: config)
    }

    private func closeClientDetail() {
        activeClientID = nil
        hookTargetID = ServerHookTarget.defaultID
        clientStatusText = nil
        hookStatusText = nil
        clearGeneratedToken()
        loadHookDraft(from: config)
    }

    private func createClient() {
        let name = newClientName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.isEmpty == false else {
            clientStatusText = L10n.Settings.serverClientEmptyName
            return
        }

        let result = ServerClientRegistry.createClient(name: name)
        var updated = config
        updated.server.clients.append(result.client)

        do {
            try ConfigLoader.save(updated)
            config = updated
            hookTargetID = result.client.id
            activeClientID = result.client.id
            newClientName = ""
            generatedClientToken = result.token
            generatedClientTokenClientID = result.client.id
            generatedClientTokenClientName = result.client.name
            clientStatusText = L10n.Settings.serverClientTokenGeneratedStatus
            hookStatusText = nil
            NotificationCenter.default.post(name: .tsutaeConfigDidChange, object: nil, userInfo: ["config": updated])
        } catch {
            clientStatusText = error.localizedDescription
        }
    }

    private func regenerateSelectedClientToken() {
        guard let index = selectedClientIndex(in: config) else { return }
        let result = ServerClientRegistry.regenerateToken(for: config.server.clients[index])
        var updated = config
        updated.server.clients[index] = result.client

        do {
            try ConfigLoader.save(updated)
            config = updated
            generatedClientToken = result.token
            generatedClientTokenClientID = result.client.id
            generatedClientTokenClientName = result.client.name
            clientStatusText = L10n.Settings.serverClientRegeneratedStatus + ". " + L10n.Settings.serverClientTokenGeneratedStatus
            NotificationCenter.default.post(name: .tsutaeConfigDidChange, object: nil, userInfo: ["config": updated])
        } catch {
            clientStatusText = error.localizedDescription
        }
    }

    private func setSelectedClientEnabled(_ enabled: Bool) {
        guard let index = selectedClientIndex(in: config) else { return }
        var updated = config
        updated.server.clients[index].enabled = enabled
        do {
            try ConfigLoader.save(updated)
            config = updated
            clientStatusText = L10n.Settings.serverSavedStatus
            NotificationCenter.default.post(name: .tsutaeConfigDidChange, object: nil, userInfo: ["config": updated])
        } catch {
            clientStatusText = error.localizedDescription
        }
    }

    private func clientScopeBinding(_ scope: Config.ServerClientScope, clientID: String) -> Binding<Bool> {
        Binding(
            get: {
                config.server.clients.first { $0.id == clientID }?.scopes.contains(scope) ?? false
            },
            set: { enabled in
                setClientScope(scope, enabled: enabled, clientID: clientID)
            }
        )
    }

    private func setClientScope(_ scope: Config.ServerClientScope, enabled: Bool, clientID: String) {
        guard let index = config.server.clients.firstIndex(where: { $0.id == clientID }) else { return }
        var updated = config
        var scopes = updated.server.clients[index].scopes
        if enabled {
            if scopes.contains(scope) == false {
                scopes.append(scope)
            }
        } else {
            scopes.removeAll { $0 == scope }
        }
        updated.server.clients[index].scopes = scopes

        do {
            try ConfigLoader.save(updated)
            config = updated
            clientStatusText = L10n.Settings.serverSavedStatus
            NotificationCenter.default.post(name: .tsutaeConfigDidChange, object: nil, userInfo: ["config": updated])
        } catch {
            clientStatusText = error.localizedDescription
        }
    }

    private func copyGeneratedClientToken() {
        guard let generatedClientToken else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(generatedClientToken, forType: .string)
        clientStatusText = L10n.Settings.serverClientTokenCopiedStatus
    }

    private func clearGeneratedTokenIfNeeded() {
        guard generatedClientTokenClientID != selectedClient?.id else { return }
        clearGeneratedToken()
    }

    private func clearGeneratedToken() {
        generatedClientToken = nil
        generatedClientTokenClientID = nil
        generatedClientTokenClientName = nil
    }

    private func selectedClient(in config: Config) -> Config.ServerClientConfig? {
        guard hookTargetID != ServerHookTarget.defaultID else { return nil }
        return config.server.clients.first { $0.id == hookTargetID }
    }

    private func selectedClientIndex(in config: Config) -> Int? {
        guard hookTargetID != ServerHookTarget.defaultID else { return nil }
        return config.server.clients.firstIndex { $0.id == hookTargetID }
    }

    private func clientHookSummary(_ client: Config.ServerClientConfig) -> String {
        let count = [
            client.hooks.onTranscribed.enabled,
            client.hooks.onSpoken.enabled,
            client.hooks.onError.enabled
        ].filter { $0 }.count
        return count > 0 ? L10n.Settings.serverHooksConfiguredCount(count) : L10n.Settings.valueConfigurable
    }

    private func clientHookEnabled(_ client: Config.ServerClientConfig) -> Bool {
        client.hooks.onTranscribed.enabled || client.hooks.onSpoken.enabled || client.hooks.onError.enabled
    }

    private func clientScopeTitle(_ scope: Config.ServerClientScope) -> String {
        switch scope {
        case .state:
            return L10n.Settings.serverEndpointState
        case .models:
            return "Models"
        case .transcribe:
            return L10n.Settings.serverEndpointSTT
        case .audioSpeech:
            return L10n.Settings.serverEndpointTTSAudio
        case .speak:
            return L10n.Settings.serverEndpointSpeak
        case .notify:
            return L10n.Settings.serverEndpointNotify
        case .stop:
            return L10n.Settings.serverEndpointStop
        case .listen:
            return "Listen (Planned)"
        case .recipes:
            return "Recipes"
        case .secrets:
            return "Secrets"
        case .configRead:
            return "Config Read"
        }
    }

    private func clientScopeDescription(_ scope: Config.ServerClientScope) -> String {
        switch scope {
        case .state:
            return "Read current app state and latest text."
        case .models:
            return "List STT/TTS engines and voices."
        case .transcribe:
            return "POST /v1/audio/transcriptions."
        case .audioSpeech:
            return "POST /v1/audio/speech."
        case .speak:
            return "Ask Tsutae to speak text."
        case .notify:
            return "Send notification or speak requests."
        case .stop:
            return "Stop current playback or work."
        case .listen:
            return "Reserved for future live listening."
        case .recipes:
            return "Read saved server recipes."
        case .secrets:
            return "List secret names only, not values."
        case .configRead:
            return "Read Tsutae configuration."
        }
    }

    private func testSelectedHook() async {
        guard saveHookDraft(showStatus: false) else { return }
        await MainActor.run {
            isTestingHook = true
            hookStatusText = L10n.Settings.serverHookTestingStatus
        }
        let event = selectedHookEvent
        let result = await hookController.testServerHook(event, client: selectedClient)
        await MainActor.run {
            isTestingHook = false
            if result.ok {
                hookStatusText = L10n.Settings.serverHookTestPassedStatus
            } else {
                hookStatusText = L10n.Settings.serverHookTestFailedStatus(result.error ?? L10n.Settings.notifyFailed(""))
            }
        }
    }

    private func refreshHealth() async {
        await MainActor.run {
            healthState = .checking
            statusText = L10n.Settings.serverHealthCheckingStatus
        }
        let healthURLString = baseURLString + "/health"
        guard let url = URL(string: healthURLString) else {
            await MainActor.run {
                healthState = .offline(L10n.Settings.serverInvalidBind)
                statusText = L10n.Settings.serverHealthOfflineStatus(L10n.Settings.serverInvalidBind)
            }
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                await MainActor.run {
                    let message = "HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)"
                    healthState = .offline(message)
                    statusText = L10n.Settings.serverHealthOfflineStatus(message)
                }
                return
            }
            let health = try JSONDecoder().decode(HealthStatus.self, from: data)
            await MainActor.run {
                healthState = .online(health)
                statusText = L10n.Settings.serverHealthOnlineStatus(health.status)
            }
        } catch {
            await MainActor.run {
                healthState = .offline(error.localizedDescription)
                statusText = L10n.Settings.serverHealthOfflineStatus(error.localizedDescription)
            }
        }
    }

    private func copyEndpoint(id: String, title: String, path: String) {
        let value = path.isEmpty ? baseURLString : baseURLString + path
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        copiedEndpointID = id
        statusText = L10n.Settings.serverCopiedEndpoint(title)
    }
}

private struct ServerEndpointRow: View {
    let title: String
    let path: String
    let isCopied: Bool
    let copy: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(colorScheme == .dark ? DS.color.foregroundDark : DS.color.foreground)
                Text(path)
                    .font(DS.font.mono(size: 11, weight: .regular))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(colorScheme == .dark ? DS.color.mutedDark : DS.color.muted)
            }

            Spacer(minLength: 10)

            Button(action: copy) {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(SettingsIconButtonStyle())
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 46, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(colorScheme == .dark ? DS.color.surface2Dark.opacity(0.66) : Color.white.opacity(0.58))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(colorScheme == .dark ? DS.color.borderDarkSoft.opacity(0.34) : DS.color.borderSoft.opacity(0.42), lineWidth: 1)
                )
        )
    }
}

struct PermissionsSettingsPage: View {
    @State private var snapshot = PermissionStatusSnapshot.placeholder
    @AppStorage("settings.permissions.focus") private var focusedPermissionRaw = ""

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsTokens.Spacing.card) {
            PermissionCard(
                title: L10n.Settings.permissionsMicrophoneTitle,
                status: L10n.Settings.permissionsMicrophoneSubtitle,
                badgeTitle: snapshot.microphone.badgeTitle,
                badgeTone: snapshot.microphone.badgeTone,
                actionTitle: snapshot.microphone.actionTitle,
                isHighlighted: focusedPermission == .microphone
            ) {
                FloatingRecordingBar.shared.openSystemSettingsPrivacyPane("Privacy_Microphone")
            }
            PermissionCard(
                title: L10n.Settings.permissionsSpeechRecognitionTitle,
                status: L10n.Settings.permissionsSpeechRecognitionSubtitle,
                badgeTitle: snapshot.speechRecognition.badgeTitle,
                badgeTone: snapshot.speechRecognition.badgeTone,
                actionTitle: snapshot.speechRecognition.actionTitle,
                isHighlighted: focusedPermission == .speechRecognition
            ) {
                FloatingRecordingBar.shared.openSystemSettingsPrivacyPane("Privacy_SpeechRecognition")
            }
            PermissionCard(
                title: L10n.Settings.permissionsAccessibilityTitle,
                status: L10n.Settings.permissionsAccessibilitySubtitle,
                badgeTitle: snapshot.accessibility.badgeTitle,
                badgeTone: snapshot.accessibility.badgeTone,
                actionTitle: snapshot.accessibility.actionTitle,
                isHighlighted: focusedPermission == .accessibility
            ) {
                FloatingRecordingBar.shared.openSystemSettingsPrivacyPane("Privacy_Accessibility")
            }
            PermissionCard(
                title: L10n.Settings.permissionsNotificationsTitle,
                status: L10n.Settings.permissionsNotificationsSubtitle,
                badgeTitle: snapshot.notifications.badgeTitle,
                badgeTone: snapshot.notifications.badgeTone,
                actionTitle: snapshot.notifications.actionTitle,
                isHighlighted: focusedPermission == .notifications
            ) {
                FloatingRecordingBar.shared.openSystemSettingsPrivacyPane("Notifications")
            }
        }
        .task {
            await refreshSnapshot()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task {
                await refreshSnapshot()
            }
        }
        .onDisappear {
            focusedPermissionRaw = ""
        }
    }

    private var focusedPermission: PermissionKind? {
        PermissionKind(rawValue: focusedPermissionRaw)
    }

    private func refreshSnapshot() async {
        let latest = await PermissionStatusSnapshot.capture()
        snapshot = latest
        if let focusedPermission, latest.state(for: focusedPermission) == .allowed {
            focusedPermissionRaw = ""
        }
    }
}

struct DeveloperToolsPage: View {
    @ObservedObject var store: STTSettingsStore
    @ObservedObject private var residencyCoordinator = LocalSTTResidencyCoordinator.shared
    @State private var debugSpeechText = "Kanade finished the latest check and is ready to report back."
    @State private var debugNotifyText = "Build succeeded for main."
    @State private var notifyLevelSelection = TTSNotifyLevel.info.rawValue
    @State private var notifyStatusText = L10n.Settings.ttsStatusIdle
    @State private var notifyStatusTone: ServerStatusCapsule.Tone = .soft
    @State private var isSendingNotify = false
    @State private var playbackSnapshot = TTSPlaybackManager.shared.snapshot()

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsTokens.Spacing.section) {
            SettingsDashboardCard(title: L10n.Settings.developerWarmupGateTitle, subtitle: L10n.Settings.developerWarmupGateSubtitle) {
                VStack(alignment: .leading, spacing: SettingsTokens.Padding.sidebarHorizontal) {
                    HStack(spacing: 8) {
                        ServerStatusCapsule(title: store.selectedModelTitle, tone: .active)
                        if residencyCoordinator.warmingModelID == store.selectedModelID {
                            ServerStatusCapsule(title: L10n.Settings.developerWarming, tone: .soft)
                        }
                    }

                    SettingsKeyValueList(rows: [
                        (L10n.Settings.sttModeLabel, store.modeTitle),
                        (L10n.Settings.sttSelectedModelLabel, store.selectedModelTitle),
                        (L10n.Settings.developerWarmGateLabel, residencyCoordinator.warmingModelID == store.selectedModelID ? L10n.Settings.developerWarmGateArmed : L10n.Settings.developerWarmGateIdle)
                    ])

                    HStack(spacing: 10) {
                        Button(L10n.Settings.developerTestWarmGate) {
                            residencyCoordinator.prepareWarmupGateTest(config: store.config)
                        }
                        .buttonStyle(SettingsAccentButtonStyle())

                        Button(L10n.Settings.developerRefreshDiskState) {
                            store.refreshDiskState()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            SettingsDashboardCard(title: L10n.Settings.developerHowToTestTitle, subtitle: L10n.Settings.developerHowToTestSubtitle) {
                SettingsKeyValueList(rows: [
                    ("1", L10n.Settings.developerHowToTestStep1),
                    ("2", L10n.Settings.developerHowToTestStep2),
                    ("3", L10n.Settings.developerHowToTestStep3),
                    (L10n.Settings.developerHowToTestExpectedLabel, L10n.Settings.developerHowToTestExpected)
                ])
            }

            SettingsDashboardCard(title: L10n.Settings.developerTTSProbeTitle, subtitle: L10n.Settings.developerTTSProbeSubtitle) {
                VStack(alignment: .leading, spacing: 14) {
                    SettingsInlineTextField(text: $debugSpeechText, placeholder: L10n.Settings.developerTTSProbePlaceholder)
                    HStack(spacing: 10) {
                        Button(playbackSnapshot.state == .idle ? L10n.Settings.developerTTSProbePlay : L10n.Settings.developerTTSProbeStop) {
                            if playbackSnapshot.state == .idle {
                                triggerDebugSpeak()
                            } else {
                                TTSPlaybackManager.shared.stop()
                            }
                        }
                        .buttonStyle(SettingsAccentButtonStyle())

                        ServerStatusCapsule(
                            title: playbackSnapshot.state == .idle ? L10n.Settings.ttsStatusIdle : L10n.Settings.ttsStatusSpeaking,
                            tone: playbackSnapshot.state == .idle ? .soft : .active
                        )
                    }
                }
            }

            SettingsDashboardCard(title: L10n.Settings.developerNotifyProbeTitle, subtitle: L10n.Settings.developerNotifyProbeSubtitle) {
                VStack(alignment: .leading, spacing: 14) {
                    SettingsInlineTextField(text: $debugNotifyText, placeholder: L10n.Settings.developerNotifyProbePlaceholder)

                    HStack(spacing: 10) {
                        Text(L10n.Settings.labelLevel)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)

                        SettingsChipSelector(
                            selection: $notifyLevelSelection,
                            options: [
                                (TTSNotifyLevel.info.rawValue, L10n.Settings.notifyLevelInfo),
                                (TTSNotifyLevel.warning.rawValue, L10n.Settings.notifyLevelWarning),
                                (TTSNotifyLevel.error.rawValue, L10n.Settings.notifyLevelError)
                            ]
                        )
                    }

                    HStack(spacing: 10) {
                        Button(isSendingNotify ? L10n.Settings.notifySending : L10n.Settings.developerNotifyProbeSpeakButton) {
                            triggerDebugNotify(speak: true, notify: false)
                        }
                        .buttonStyle(SettingsAccentButtonStyle())
                        .disabled(isSendingNotify)

                        Button(L10n.Settings.developerNotifyProbeNotificationButton) {
                            triggerDebugNotify(speak: false, notify: true)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isSendingNotify)

                        Button(L10n.Settings.developerNotifyProbeBothButton) {
                            triggerDebugNotify(speak: true, notify: true)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isSendingNotify)

                        ServerStatusCapsule(title: notifyStatusText, tone: notifyStatusTone)
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tsutaeTTSPlaybackDidChange)) { _ in
            playbackSnapshot = TTSPlaybackManager.shared.snapshot()
        }
    }

    private func triggerDebugSpeak() {
        let config = (try? ConfigLoader.load()) ?? .default
        var ttsConfig = config.tts
        TTSGeneralPresentationStyle.applyCurrent(to: &ttsConfig)
        Task {
            do {
                _ = try await TTSPlaybackManager.shared.speak(
                    TTSSpeakRequest(
                        text: debugSpeechText,
                        source: "developer",
                        interrupt: true,
                        voice: nil,
                        rate: ttsConfig.rate,
                        presentationStyle: ttsConfig.presentationStyle
                    ),
                    config: ttsConfig
                )
            } catch {
                playbackSnapshot = TTSPlaybackManager.shared.snapshot()
            }
        }
    }

    private func triggerDebugNotify(speak: Bool, notify: Bool) {
        isSendingNotify = true
        notifyStatusText = L10n.Settings.notifySending
        notifyStatusTone = .soft
        let request = TTSNotifyRequest(
            message: debugNotifyText,
            title: "Tsutae",
            level: TTSNotifyLevel(rawValue: notifyLevelSelection) ?? .info,
            interruptible: true,
            fallbackToNotification: true,
            notify: notify,
            speak: speak
        )
        Task {
            do {
                let response = try await DefaultAppController().notify(request)
                await MainActor.run {
                    isSendingNotify = false
                    notifyStatusText = notifyStatusText(for: response)
                    notifyStatusTone = response.ok ? .active : .warning
                }
            } catch {
                await MainActor.run {
                    isSendingNotify = false
                    notifyStatusText = L10n.Settings.notifyFailed(error.localizedDescription)
                    notifyStatusTone = .warning
                }
            }
        }
    }

    private func notifyStatusText(for response: TTSNotifyResponse) -> String {
        if response.spoken && response.notificationDelivered {
            return L10n.Settings.notifySentBoth
        }
        if response.spoken {
            return response.state == .queued ? L10n.Settings.notifyQueued : L10n.Settings.notifySentSpeak
        }
        if response.notificationDelivered {
            return response.fallbackUsed ? L10n.Settings.notifyFallbackNotificationSent : L10n.Settings.notifySentNotification
        }
        return response.error.map(L10n.Settings.notifyFailed) ?? L10n.Settings.notifyFailed("")
    }
}

private struct SettingsToggleRow<Trailing: View>: View {
    let title: String
    let subtitle: String
    let isOn: Binding<Bool>
    let badgeTitle: String
    let badgeTone: ServerStatusCapsule.Tone
    @ViewBuilder var trailing: Trailing

    init(
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        badgeTitle: String,
        badgeTone: ServerStatusCapsule.Tone,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.isOn = isOn
        self.badgeTitle = badgeTitle
        self.badgeTone = badgeTone
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                ServerStatusCapsule(title: badgeTitle, tone: badgeTone)
                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .toggleStyle(SettingsSwitchToggleStyle())
                trailing
            }
        }
    }
}

private struct SettingsSwitchToggleStyle: ToggleStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                configuration.isOn.toggle()
            }
        } label: {
            RoundedRectangle(cornerRadius: SettingsTokens.Size.toggleTrackHeight / 2, style: .continuous)
                .fill(configuration.isOn ? DS.color.accent.opacity(colorScheme == .dark ? 0.85 : 0.9) : (colorScheme == .dark ? DS.color.surface3Dark.opacity(0.9) : DS.color.surface.opacity(0.95)))
                .overlay(
                    Circle()
                        .fill(Color.white.opacity(configuration.isOn ? 0.98 : 0.92))
                        .frame(width: SettingsTokens.Size.toggleThumb, height: SettingsTokens.Size.toggleThumb)
                        .shadow(color: .black.opacity(0.16), radius: 4, x: 0, y: 1)
                        .offset(x: configuration.isOn ? 8 : -8)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: SettingsTokens.Size.toggleTrackHeight / 2, style: .continuous)
                        .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.08) : DS.color.borderSoft.opacity(0.48), lineWidth: 1)
                )
                .frame(width: SettingsTokens.Size.toggleTrackWidth, height: SettingsTokens.Size.toggleTrackHeight)
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsIconButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(colorScheme == .dark ? DS.color.foregroundDark.opacity(0.82) : DS.color.soft)
            .frame(width: SettingsTokens.Size.iconButton, height: SettingsTokens.Size.iconButton)
            .background(
                Circle()
                    .fill(configuration.isPressed ? DS.color.accent.opacity(0.14) : (colorScheme == .dark ? DS.color.surface2Dark.opacity(0.78) : Color.white.opacity(0.74)))
                    .overlay(
                        Circle()
                            .strokeBorder(colorScheme == .dark ? DS.color.borderDarkSoft.opacity(0.42) : DS.color.borderSoft.opacity(0.52), lineWidth: 1)
                    )
            )
    }
}

private struct TTSMultilineFormRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: SettingsTokens.Spacing.card) {
            Text(label)
                .font(.system(size: 14, weight: .regular))
                .lineLimit(1)
                .foregroundStyle(colorScheme == .dark ? DS.color.foregroundDark : DS.color.foreground)
                .frame(width: SettingsTokens.Width.formLabel, alignment: .leading)
                .padding(.top, 10)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, SettingsTokens.Padding.sectionHorizontal)
        .padding(.vertical, 6)
    }
}

private struct SettingsInlineTextField: View {
    @Binding var text: String
    let placeholder: String
    var width: CGFloat? = nil
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .lineLimit(1)
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(colorScheme == .dark ? DS.color.foregroundDark : DS.color.foreground)
            .padding(.horizontal, 12)
            .frame(width: width, height: SettingsTokens.Size.controlHeight, alignment: .leading)
            .background(fieldBackground(cornerRadius: 13))
    }

    private func fieldBackground(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(colorScheme == .dark ? DS.color.surface2Dark.opacity(0.92) : Color.white.opacity(0.88))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(colorScheme == .dark ? DS.color.borderDarkSoft.opacity(0.42) : DS.color.borderSoft.opacity(0.62), lineWidth: 1)
            )
    }
}

private struct SettingsInlineMultilineTextField: View {
    @Binding var text: String
    let placeholder: String
    var width: CGFloat? = nil
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .textFieldStyle(.plain)
            .lineLimit(3...5)
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(colorScheme == .dark ? DS.color.foregroundDark : DS.color.foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(width: width, alignment: .topLeading)
            .frame(minHeight: 74, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(colorScheme == .dark ? DS.color.surface2Dark.opacity(0.92) : Color.white.opacity(0.88))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(colorScheme == .dark ? DS.color.borderDarkSoft.opacity(0.42) : DS.color.borderSoft.opacity(0.62), lineWidth: 1)
                    )
            )
    }
}

private struct SettingsInlineSecureField: View {
    @Binding var text: String
    @Binding var isRevealed: Bool
    let placeholder: String
    var width: CGFloat? = nil
    var onReveal: (() -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if isRevealed {
                    TextField(placeholder, text: $text)
                } else {
                    SecureField(placeholder, text: $text)
                }
            }
            .textFieldStyle(.plain)
            .lineLimit(1)
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(colorScheme == .dark ? DS.color.foregroundDark : DS.color.foreground)

            Button {
                let nextValue = !isRevealed
                if nextValue { onReveal?() }
                isRevealed = nextValue
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DS.color.accent)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(width: width, height: SettingsTokens.Size.controlHeight, alignment: .leading)
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

// MARK: - Placeholder View

struct SettingsPlaceholderView: View {

    let tab: SettingsTab

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsTokens.Spacing.section) {
            SettingsSection(title: tab.title) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.Settings.placeholderTitle(tab.title))
                        .font(.headline)
                    Text(L10n.Settings.placeholderDescription)
                        .foregroundStyle(.secondary)
                }
                .padding(SettingsTokens.Padding.card)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Reusable Components
