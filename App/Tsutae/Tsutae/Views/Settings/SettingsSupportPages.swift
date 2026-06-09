import AppKit
import AVFoundation
import Speech
import SwiftUI
import TsutaeCore
import UserNotifications

struct TTSSettingsPage: View {
    @State private var config = (try? ConfigLoader.load()) ?? .default
    @State private var previewText = "Tsutae can announce this update for you."
    @State private var playbackSnapshot = TTSPlaybackManager.shared.snapshot()
    @State private var availableTTSEngines: [EngineInfo] = []
    @State private var availableVoices: [Voice] = []

    var body: some View {
        SettingsTwoColumnGrid {
            SettingsDashboardCard(title: L10n.Settings.ttsVoiceEngineTitle, subtitle: L10n.Settings.ttsVoiceEngineSubtitle) {
                VStack(spacing: 0) {
                    SettingsFormRow(label: L10n.Settings.labelProvider) {
                        SettingsDropdown(
                            selection: engineSelection,
                            options: engineOptions,
                            tone: .active,
                            width: SettingsTokens.Width.modeDropdown,
                            menuWidth: SettingsTokens.Width.modeDropdown
                        )
                    }
                    SettingsDivider()
                    SettingsFormRow(label: L10n.Settings.labelVoice) {
                        SettingsDropdown(
                            selection: voiceSelection,
                            options: voiceOptions,
                            width: 280,
                            menuWidth: 320
                        )
                    }
                    SettingsDivider()
                    SettingsFormRow(label: L10n.Settings.labelSpeed) {
                        HStack(spacing: 14) {
                            Slider(value: rateSelection, in: 0.7...1.6, step: 0.05)
                                .frame(width: 180)
                            Text(String(format: "%.2fx", config.tts.rate))
                                .font(DS.font.mono(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    SettingsDivider()
                    SettingsFormRow(label: L10n.Settings.labelOutput) {
                        ServerStatusCapsule(title: L10n.Settings.valueSystem, tone: .soft)
                    }
                }
            }
            
            SettingsDashboardCard(title: L10n.Settings.ttsPlaybackTitle, subtitle: L10n.Settings.ttsPlaybackSubtitle) {
                VStack(spacing: 0) {
                    SettingsFormRow(label: L10n.Settings.ttsPresentationStyleLabel) {
                        SettingsChipSelector(
                            selection: presentationStyleSelection,
                            options: [
                                (Config.TTSPresentationStyle.standard.rawValue, L10n.Settings.ttsStyleStandard),
                                (Config.TTSPresentationStyle.minimal.rawValue, L10n.Settings.ttsStyleMinimal)
                            ]
                        )
                    }
                    SettingsDivider()
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
                    SettingsFormRow(label: L10n.Settings.labelStatus) {
                        ServerStatusCapsule(
                            title: playbackSnapshot.state == .idle ? L10n.Settings.ttsStatusIdle : L10n.Settings.ttsStatusSpeaking,
                            tone: playbackSnapshot.state == .idle ? .soft : .active
                        )
                    }
                    SettingsDivider()
                    SettingsFormRow(label: L10n.Settings.labelQueue) {
                        ServerStatusCapsule(title: L10n.Settings.valueSingleResponse, tone: .neutral)
                    }
                }
            }
            
            SettingsDashboardCard(title: L10n.Settings.ttsPreviewTitle, subtitle: L10n.Settings.ttsPreviewSubtitle) {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.Settings.ttsPreviewTextLabel)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        SettingsInlineTextField(text: $previewText, placeholder: L10n.Settings.ttsPreviewPlaceholder)
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
                        
                        ServerStatusCapsule(
                            title: playbackSnapshot.state == .idle ? L10n.Settings.ttsStatusIdle : L10n.Settings.ttsStatusSpeaking,
                            tone: playbackSnapshot.state == .idle ? .soft : .active
                        )
                    }
                }
            }
            
            SettingsDashboardCard(title: L10n.Settings.ttsIntegrationTitle, subtitle: L10n.Settings.ttsIntegrationSubtitle) {
                SettingsKeyValueList(rows: [
                    (L10n.Settings.labelServerExposure, config.server.autoStart ? L10n.Settings.toggleOn : L10n.Settings.toggleOff),
                    (L10n.Settings.labelCallbacks, "/v1/speak"),
                    (L10n.Settings.labelHooks, "/v1/stop"),
                    (L10n.Settings.labelStreaming, L10n.Settings.valueFuture)
                ])
            }
        }
        .onAppear {
            refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tsutaeTTSPlaybackDidChange)) { _ in
            playbackSnapshot = TTSPlaybackManager.shared.snapshot()
        }
    }
    
    private var engineOptions: [SettingsDropdownOption] {
        availableTTSEngines.map { SettingsDropdownOption(id: $0.id, title: $0.displayName) }
    }
    
    private var voiceOptions: [SettingsDropdownOption] {
        [SettingsDropdownOption(id: "", title: L10n.Settings.valueDefault)] + availableVoices.map {
            SettingsDropdownOption(id: $0.id, title: "\($0.displayName) · \($0.language)")
        }
    }
    
    private var engineSelection: Binding<String> {
        Binding(
            get: { config.tts.engine },
            set: { newValue in
                updateConfig { $0.tts.engine = newValue }
                refreshVoices()
            }
        )
    }
    
    private var voiceSelection: Binding<String> {
        Binding(
            get: { config.tts.voice ?? "" },
            set: { newValue in
                updateConfig { $0.tts.voice = newValue.isEmpty ? nil : newValue }
            }
        )
    }
    
    private var presentationStyleSelection: Binding<String> {
        Binding(
            get: { config.tts.presentationStyle.rawValue },
            set: { newValue in
                guard let style = Config.TTSPresentationStyle(rawValue: newValue) else { return }
                updateConfig { $0.tts.presentationStyle = style }
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
    
    private var rateSelection: Binding<Double> {
        Binding(
            get: { config.tts.rate },
            set: { newValue in
                updateConfig { $0.tts.rate = newValue }
            }
        )
    }
    
    private func refresh() {
        config = (try? ConfigLoader.load()) ?? .default
        playbackSnapshot = TTSPlaybackManager.shared.snapshot()
        availableTTSEngines = EngineManager.shared.listTTS()
        refreshVoices()
    }
    
    private func refreshVoices() {
        if config.tts.engine == AppleTTSEngine.shared.id {
            availableVoices = AppleTTSEngine.shared.voices
        } else {
            availableVoices = []
        }
    }
    
    private func triggerPreview() {
        do {
            _ = try TTSPlaybackManager.shared.speak(
                TTSSpeakRequest(
                    text: previewText,
                    source: "Tsutae",
                    interrupt: true,
                    voice: config.tts.voice,
                    rate: config.tts.rate,
                    presentationStyle: config.tts.presentationStyle
                ),
                config: config.tts
            )
        } catch {
            playbackSnapshot = TTSPlaybackManager.shared.snapshot()
        }
    }
    
    private func updateConfig(_ mutate: (inout Config) -> Void) {
        var updated = config
        mutate(&updated)
        config = updated
        do {
            try ConfigLoader.save(updated)
            NotificationCenter.default.post(name: .tsutaeConfigDidChange, object: nil)
        } catch {
            config = (try? ConfigLoader.load()) ?? config
        }
    }
}

struct ServerSettingsPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: SettingsTokens.Spacing.section) {
            SettingsDashboardCard(title: L10n.Settings.serverRuntimeTitle, subtitle: L10n.Settings.serverRuntimeSubtitle) {
                HStack(spacing: SettingsTokens.Padding.sidebarHorizontal) {
                    ServerStatusCapsule(title: L10n.Settings.valueStopped, tone: .neutral)
                    ServerStatusCapsule(title: "127.0.0.1:1338", tone: .soft)
                    Spacer()
                }
            }
            
            SettingsTwoColumnGrid {
                SettingsDashboardCard(title: L10n.Settings.serverCapabilitiesTitle, subtitle: L10n.Settings.serverCapabilitiesSubtitle) {
                    SettingsKeyValueList(rows: [
                        (L10n.Settings.labelSTT, L10n.Settings.valuePlanned),
                        (L10n.Settings.labelTTS, L10n.Settings.valuePlanned),
                        (L10n.Settings.labelHooks, L10n.Settings.valuePlanned),
                        (L10n.Settings.labelCallbacks, L10n.Settings.valuePlanned)
                    ])
                }
                
                SettingsDashboardCard(title: L10n.Settings.serverAccessTitle, subtitle: L10n.Settings.serverAccessSubtitle) {
                    SettingsKeyValueList(rows: [
                        (L10n.Settings.labelBaseURL, L10n.Settings.valueLocalhost),
                        (L10n.Settings.labelAuthToken, L10n.Settings.valueManaged),
                        (L10n.Settings.labelCORS, L10n.Settings.valueConfigurable),
                        (L10n.Settings.labelCopyEndpoint, L10n.Settings.valueShortcut)
                    ])
                }
                
                SettingsDashboardCard(title: L10n.Settings.serverHooksTitle, subtitle: L10n.Settings.serverHooksSubtitle) {
                    SettingsKeyValueList(rows: [
                        (L10n.Settings.labelOnTranscribed, L10n.Settings.valuePlanned),
                        (L10n.Settings.labelOnSpoken, L10n.Settings.valuePlanned),
                        (L10n.Settings.labelOnError, L10n.Settings.valuePlanned)
                    ])
                }
                
                SettingsDashboardCard(title: L10n.Settings.serverHealthTitle, subtitle: L10n.Settings.serverHealthSubtitle) {
                    SettingsMetricStack(items: [
                        (L10n.Settings.labelStatus, L10n.Settings.valuePrototype),
                        (L10n.Settings.labelRecentRequests, "—"),
                        (L10n.Settings.labelLastError, "—")
                    ], accent: .blue)
                }
            }
        }
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
        }
        .onReceive(NotificationCenter.default.publisher(for: .tsutaeTTSPlaybackDidChange)) { _ in
            playbackSnapshot = TTSPlaybackManager.shared.snapshot()
        }
    }
    
    private func triggerDebugSpeak() {
        let config = (try? ConfigLoader.load()) ?? .default
        do {
            _ = try TTSPlaybackManager.shared.speak(
                TTSSpeakRequest(
                    text: debugSpeechText,
                    source: "developer",
                    interrupt: true,
                    voice: config.tts.voice,
                    rate: config.tts.rate,
                    presentationStyle: config.tts.presentationStyle
                ),
                config: config.tts
            )
        } catch {
            playbackSnapshot = TTSPlaybackManager.shared.snapshot()
        }
    }
}

private struct SettingsInlineTextField: View {
    @Binding var text: String
    let placeholder: String
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .lineLimit(2...3)
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(colorScheme == .dark ? DS.color.foregroundDark : DS.color.foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
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

