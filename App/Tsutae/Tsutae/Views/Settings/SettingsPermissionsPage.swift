import AppKit
import SwiftUI

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

