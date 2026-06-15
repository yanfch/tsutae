import SwiftUI
import TsutaeCore

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

