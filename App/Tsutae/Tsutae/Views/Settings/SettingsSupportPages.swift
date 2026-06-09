import AppKit
import AVFoundation
import Speech
import SwiftUI
import TsutaeCore
import UserNotifications

struct TTSSettingsPage: View {
    var body: some View {
        SettingsTwoColumnGrid {
            SettingsDashboardCard(title: L10n.Settings.ttsVoiceEngineTitle, subtitle: L10n.Settings.ttsVoiceEngineSubtitle) {
                SettingsKeyValueList(rows: [
                    (L10n.Settings.labelProvider, L10n.Settings.valuePrototype),
                    (L10n.Settings.labelVoice, L10n.Settings.valueDefault),
                    (L10n.Settings.labelSpeed, "1.0x"),
                    (L10n.Settings.labelOutput, L10n.Settings.valueSystem)
                ])
            }
            
            SettingsDashboardCard(title: L10n.Settings.ttsPlaybackTitle, subtitle: L10n.Settings.ttsPlaybackSubtitle) {
                SettingsKeyValueList(rows: [
                    (L10n.Settings.labelAutoPlay, L10n.Settings.toggleOff),
                    (L10n.Settings.labelInterrupt, L10n.Settings.valueAllowed),
                    (L10n.Settings.labelQueue, L10n.Settings.valueSingleResponse)
                ])
            }
            
            SettingsDashboardCard(title: L10n.Settings.ttsPreviewTitle, subtitle: L10n.Settings.ttsPreviewSubtitle) {
                SettingsMetricStack(items: [
                    (L10n.Settings.labelStatus, L10n.Settings.valuePlanned),
                    (L10n.Settings.labelSample, L10n.Settings.valueComingSoon),
                    (L10n.Settings.labelHooks, L10n.Settings.valueCompatible)
                ], accent: .orange)
            }
            
            SettingsDashboardCard(title: L10n.Settings.ttsIntegrationTitle, subtitle: L10n.Settings.ttsIntegrationSubtitle) {
                SettingsKeyValueList(rows: [
                    (L10n.Settings.labelServerExposure, L10n.Settings.valuePlanned),
                    (L10n.Settings.labelCallbacks, L10n.Settings.valueSupported),
                    (L10n.Settings.labelStreaming, L10n.Settings.valueFuture)
                ])
            }
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
        }
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

