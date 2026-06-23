import SwiftUI
import TsutaeCore

struct DeveloperToolsPage: View {
    @ObservedObject var store: STTSettingsStore
    @ObservedObject private var residencyCoordinator = LocalSTTResidencyCoordinator.shared
    @State private var debugSpeechText = "Kanade finished the latest check and is ready to report back."
    @State private var debugNotifyText = "Build succeeded for main."
    @State private var polishModeSelection = Config.TranscriptPostProcessingMode.smart.rawValue
    @State private var polishTaskSelection = Config.TranscriptPostProcessingTask.cleanDictation.rawValue
    @State private var polishSampleSelection = DeveloperPolishSample.shortDictation.id
    @State private var polishInputText = DeveloperPolishSample.shortDictation.text
    @State private var polishOutputText = ""
    @State private var polishRemoteBaseURL = ""
    @State private var polishRemoteModel = ""
    @State private var polishRemoteAPIKey = ""
    @State private var isPolishAPIKeyRevealed = false
    @State private var polishStatusText = L10n.Settings.ttsStatusIdle
    @State private var polishStatusTone: ServerStatusCapsule.Tone = .soft
    @State private var isRunningPolish = false
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

            SettingsDashboardCard(title: L10n.Settings.developerPolishProbeTitle, subtitle: L10n.Settings.developerPolishProbeSubtitle) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Text(L10n.Settings.developerPolishModeLabel)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        SettingsChipSelector(
                            selection: $polishModeSelection,
                            options: [
                                (Config.TranscriptPostProcessingMode.smart.rawValue, L10n.Settings.developerPolishModeSmart),
                                (Config.TranscriptPostProcessingMode.rules.rawValue, L10n.Settings.developerPolishModeRules),
                                (Config.TranscriptPostProcessingMode.remote.rawValue, L10n.Settings.developerPolishModeRemote)
                            ]
                        )

                        Text(L10n.Settings.developerPolishTaskLabel)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        SettingsChipSelector(
                            selection: $polishTaskSelection,
                            options: [
                                (Config.TranscriptPostProcessingTask.cleanDictation.rawValue, L10n.Settings.developerPolishTaskClean),
                                (Config.TranscriptPostProcessingTask.rewriteMessage.rawValue, L10n.Settings.developerPolishTaskMessage),
                                (Config.TranscriptPostProcessingTask.meetingNotes.rawValue, L10n.Settings.developerPolishTaskMeeting)
                            ]
                        )
                    }

                    SettingsSection(title: L10n.Settings.developerPolishRemoteTitle) {
                        SettingsFormRow(label: L10n.Settings.labelBaseURL) {
                            SettingsInlineTextField(text: $polishRemoteBaseURL, placeholder: "https://api.openai.com/v1", width: SettingsTokens.Size.remoteFieldWidth)
                        }
                        SettingsFormRow(label: L10n.Settings.sttRemoteModelLabel) {
                            SettingsInlineTextField(text: $polishRemoteModel, placeholder: "gpt-4.1-mini", width: SettingsTokens.Size.remoteFieldWidth)
                        }
                        SettingsFormRow(label: L10n.Settings.sttRemoteAPIKeyLabel, helpText: polishAPIKeyHelpText) {
                            SettingsInlineSecureField(
                                text: $polishRemoteAPIKey,
                                isRevealed: $isPolishAPIKeyRevealed,
                                placeholder: polishAPIKeyPlaceholder,
                                width: SettingsTokens.Size.remoteFieldWidth,
                                onReveal: {
                                    polishRemoteAPIKey = loadPostProcessingAPIKey() ?? ""
                                }
                            )
                        }
                    }

                    SettingsFormRow(label: L10n.Settings.developerPolishSampleLabel) {
                        SettingsDropdown(
                            selection: $polishSampleSelection,
                            options: DeveloperPolishSample.allCases.map { .init(id: $0.id, title: $0.title) },
                            width: SettingsTokens.Size.remoteFieldWidth
                        )
                    }

                    TTSMultilineFormRow(label: L10n.Settings.developerPolishInputLabel) {
                        SettingsInlineMultilineTextField(text: $polishInputText, placeholder: L10n.Settings.developerPolishInputPlaceholder, width: nil)
                    }

                    TTSMultilineFormRow(label: L10n.Settings.developerPolishOutputLabel) {
                        DeveloperPolishOutputView(text: polishOutputText.isEmpty ? L10n.Settings.developerPolishOutputPlaceholder : polishOutputText)
                    }

                    HStack(spacing: 10) {
                        Button(L10n.Settings.developerPolishSaveButton) {
                            savePostProcessingDraft()
                        }
                        .buttonStyle(.bordered)

                        Button(isRunningPolish ? L10n.Settings.developerPolishRunning : L10n.Settings.developerPolishRunButton) {
                            runPolishProbe()
                        }
                        .buttonStyle(SettingsAccentButtonStyle())
                        .disabled(isRunningPolish || polishInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        ServerStatusCapsule(title: polishStatusText, tone: polishStatusTone)
                    }
                }
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
                            title: playbackStatusTitle,
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
        .onAppear {
            syncPostProcessingDraftFromStore()
        }
        .onChange(of: polishSampleSelection) { _, newValue in
            guard let sample = DeveloperPolishSample(rawValue: newValue) else { return }
            polishInputText = sample.text
            polishTaskSelection = sample.task.rawValue
            polishOutputText = ""
            polishStatusText = L10n.Settings.ttsStatusIdle
            polishStatusTone = .soft
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

    private func runPolishProbe() {
        isRunningPolish = true
        polishStatusText = L10n.Settings.developerPolishRunning
        polishStatusTone = .soft
        let config = postProcessingConfigFromDraft(enabled: true)
        let task = Config.TranscriptPostProcessingTask(rawValue: polishTaskSelection) ?? .cleanDictation
        let apiKey = resolvedPostProcessingAPIKey()
        Task {
            do {
                let result = try await TranscriptPostProcessor.process(
                    polishInputText,
                    config: config,
                    task: task,
                    language: store.config.stt.language,
                    dictionaryContext: TranscriptDictionaryContext(config: store.config, appContext: "developer"),
                    apiKeyOverride: apiKey
                )
                await MainActor.run {
                    isRunningPolish = false
                    polishOutputText = result.processedText
                    let route = polishRouteLabel(for: result.mode)
                    polishStatusText = result.dictionaryMatches.isEmpty
                        ? L10n.Settings.developerPolishDone(route, result.elapsedMs)
                        : L10n.Settings.developerPolishDoneWithTerms(route, result.elapsedMs, result.dictionaryMatches.count)
                    polishStatusTone = .active
                }
            } catch {
                await MainActor.run {
                    isRunningPolish = false
                    polishStatusText = L10n.Settings.notifyFailed(error.localizedDescription)
                    polishStatusTone = .warning
                }
            }
        }
    }

    private func syncPostProcessingDraftFromStore() {
        let config = (try? ConfigLoader.load()) ?? .default
        polishModeSelection = config.postProcessing.mode.rawValue
        polishTaskSelection = config.postProcessing.defaultTask.rawValue
        polishRemoteBaseURL = config.postProcessing.remote.baseURL ?? ""
        polishRemoteModel = config.postProcessing.remote.model ?? ""
        polishRemoteAPIKey = ""
        isPolishAPIKeyRevealed = false
    }

    private func savePostProcessingDraft() {
        do {
            var config = try ConfigLoader.load()
            config.postProcessing = postProcessingConfigFromDraft(enabled: config.postProcessing.enabled)
            let trimmedAPIKey = polishRemoteAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedAPIKey.isEmpty == false {
                let ref = config.postProcessing.remote.apiKeyRef ?? "tsutae.remote_polish"
                try SecretsManager.set(trimmedAPIKey, for: ref)
                config.postProcessing.remote.apiKeyRef = ref
                polishRemoteAPIKey = ""
                isPolishAPIKeyRevealed = false
            }
            try ConfigLoader.save(config)
            polishStatusText = L10n.Settings.developerPolishSaved
            polishStatusTone = .active
        } catch {
            polishStatusText = L10n.Settings.notifyFailed(error.localizedDescription)
            polishStatusTone = .warning
        }
    }

    private func postProcessingConfigFromDraft(enabled: Bool) -> Config.TranscriptPostProcessingConfig {
        let stored = (try? ConfigLoader.load())?.postProcessing ?? Config.TranscriptPostProcessingConfig()
        return Config.TranscriptPostProcessingConfig(
            enabled: enabled,
            mode: Config.TranscriptPostProcessingMode(rawValue: polishModeSelection) ?? .smart,
            defaultTask: Config.TranscriptPostProcessingTask(rawValue: polishTaskSelection) ?? .cleanDictation,
            remote: Config.TranscriptPostProcessingRemoteConfig(
                enabled: true,
                baseURL: polishRemoteBaseURL.trimmingCharacters(in: .whitespacesAndNewlines),
                model: polishRemoteModel.trimmingCharacters(in: .whitespacesAndNewlines),
                apiKeyRef: stored.remote.apiKeyRef
            ),
            dictionary: stored.dictionary
        )
    }

    private func loadPostProcessingAPIKey() -> String? {
        guard let ref = ((try? ConfigLoader.load()) ?? .default).postProcessing.remote.apiKeyRef else { return nil }
        return try? SecretsManager.get(ref)
    }

    private func resolvedPostProcessingAPIKey() -> String? {
        let draft = polishRemoteAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if draft.isEmpty == false {
            return draft
        }
        return loadPostProcessingAPIKey()
    }

    private var polishAPIKeyPlaceholder: String {
        hasStoredPostProcessingAPIKey ? L10n.Settings.sttRemoteAPIKeyStoredPlaceholder : "sk-…"
    }

    private var polishAPIKeyHelpText: String {
        L10n.Settings.developerPolishAPIKeyHelp
    }

    private var hasStoredPostProcessingAPIKey: Bool {
        ((try? ConfigLoader.load()) ?? .default).postProcessing.remote.apiKeyRef != nil
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

    private var playbackStatusTitle: String {
        switch playbackSnapshot.state {
        case .idle:
            return L10n.Settings.ttsStatusIdle
        case .preparing:
            return L10n.Settings.ttsStatusPreparing
        case .queued:
            return L10n.Settings.notifyQueued
        case .speaking, .stopping:
            return L10n.Settings.ttsStatusSpeaking
        }
    }

    private func polishRouteLabel(for mode: Config.TranscriptPostProcessingMode) -> String {
        switch mode {
        case .off:
            return L10n.Settings.developerPolishModeOff
        case .smart:
            return L10n.Settings.developerPolishModeSmart
        case .rules:
            return L10n.Settings.developerPolishModeRules
        case .remote:
            return L10n.Settings.developerPolishModeRemote
        }
    }
}

private enum DeveloperPolishSample: String, CaseIterable, Identifiable {
    case shortDictation
    case chineseCorrection
    case spokenPunctuation
    case technicalTerms
    case messageRewrite
    case meetingNotes
    case openQuestion

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shortDictation:
            return L10n.Settings.developerPolishSampleShort
        case .chineseCorrection:
            return L10n.Settings.developerPolishSampleCorrection
        case .spokenPunctuation:
            return L10n.Settings.developerPolishSamplePunctuation
        case .technicalTerms:
            return L10n.Settings.developerPolishSampleTerms
        case .messageRewrite:
            return L10n.Settings.developerPolishTaskMessage
        case .meetingNotes:
            return L10n.Settings.developerPolishSampleMeeting
        case .openQuestion:
            return L10n.Settings.developerPolishSampleOpenQuestion
        }
    }

    var task: Config.TranscriptPostProcessingTask {
        switch self {
        case .shortDictation, .chineseCorrection, .spokenPunctuation, .technicalTerms:
            return .cleanDictation
        case .messageRewrite:
            return .rewriteMessage
        case .meetingNotes, .openQuestion:
            return .meetingNotes
        }
    }

    var text: String {
        switch self {
        case .shortDictation:
            return "um let's ship the server token change today and then uh update the readme tomorrow"
        case .chineseCorrection:
            return "呃我们周四见等等不对其实周五三点见然后把 codex hook 的通知也测一下"
        case .spokenPunctuation:
            return "请打开 git hub actions 逗号看一下 json 配置有没有错 问号 换行 然后更新 readme 句号"
        case .technicalTerms:
            return "mac os 和 ios 上的 https url 要保留 swift package manager 也要跑 stt tts 的 test"
        case .messageRewrite:
            return "嗯帮我写一下就是说我们已经把 server token 和 hook 分应用配置做好了然后下周想重点看一下 llm 整理文案和会议纪要这个能力"
        case .meetingNotes:
            return "今天会议主要说 tsutae 的发布准备。第一文档还不完整，需要补 readme 和 server api。第二 stt 本地模型长录音还是容易失败，短期提示用户分段，后面做音频切片。第三 tts local 已经能播但是第一次比较慢，需要保留 warmup 状态。下周一前我负责整理测试 case，kanade 负责接入 server token。风险是本地模型下载进度和 keychain 权限还要再测。"
        case .openQuestion:
            return "今天讨论 post processing 默认先走 rules remote 只在手动整理时触发 决策是先不上自动 remote 开放问题是长文本什么时候自动触发还没确定"
        }
    }
}

private struct DeveloperPolishOutputView: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(colorScheme == .dark ? DS.color.foregroundDark : DS.color.foreground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(12)
        }
        .frame(maxWidth: .infinity, minHeight: 86, maxHeight: 180, alignment: .topLeading)
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
