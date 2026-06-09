import AppKit
import AVFoundation
import Speech
import SwiftUI
import UserNotifications

struct SettingsTwoColumnGrid<Content: View>: View {
    @ViewBuilder let content: Content
    
    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(minimum: 280), spacing: SettingsTokens.Spacing.card, alignment: .top),
                GridItem(.flexible(minimum: 280), spacing: SettingsTokens.Spacing.card, alignment: .top)
            ],
            spacing: SettingsTokens.Spacing.card
        ) {
            content
        }
    }
}

struct SettingsDashboardCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: SettingsTokens.Spacing.content) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(DS.font.mono(size: 13, weight: .medium))
                    .tracking(0.1)
                Text(subtitle)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(colorScheme == .dark ? DS.color.mutedDark : DS.color.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            content
        }
        .padding(SettingsTokens.Padding.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SettingsCardBackground())
    }
}

struct SettingsKeyValueList: View {
    let rows: [(String, String)]
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top) {
                    Text(row.0)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(colorScheme == .dark ? DS.color.mutedDark : DS.color.muted)
                    Spacer(minLength: 16)
                    Text(row.1)
                        .font(DS.font.mono(size: 12, weight: .regular))
                        .foregroundStyle(colorScheme == .dark ? DS.color.foregroundDark : DS.color.foreground)
                }
            }
        }
    }
}

struct SettingsMetricStack: View {
    let items: [(String, String)]
    let accent: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 10) {
                    Circle()
                        .fill(accent.opacity(0.85))
                        .frame(width: 7, height: 7)
                    Text(item.0)
                        .font(.system(size: 13, weight: .regular))
                    Spacer()
                    Text(item.1)
                        .font(DS.font.mono(size: 12, weight: .medium))
                }
            }
        }
    }
}

struct WorkflowOverviewRow: View {
    private let items = [
        L10n.Settings.workflowCapture,
        L10n.Settings.workflowTranscribe,
        L10n.Settings.workflowInsert,
        L10n.Settings.workflowSpeak,
        L10n.Settings.workflowServe,
    ]
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(items.indices, id: \.self) { index in
                if index > 0 {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                
                ServerStatusCapsule(title: items[index], tone: index < 3 ? .active : .soft)
            }
            Spacer(minLength: 0)
        }
    }
}

enum PermissionKind: String {
    case microphone
    case speechRecognition
    case accessibility
    case notifications
}

struct PermissionCard: View {
    let title: String
    let status: String
    let badgeTitle: String
    let badgeTone: ServerStatusCapsule.Tone
    let actionTitle: String
    let isHighlighted: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        SettingsDashboardCard(title: title, subtitle: status) {
            HStack {
                ServerStatusCapsule(title: badgeTitle, tone: badgeTone)
                Spacer()
                Button(actionTitle, action: action)
                    .buttonStyle(SettingsGhostButtonStyle())
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isHighlighted ? DS.color.accent.opacity(0.65) : Color.clear, lineWidth: 1.5)
        }
        .shadow(color: isHighlighted ? DS.color.accent.opacity(colorScheme == .dark ? 0.2 : 0.14) : .clear, radius: 16, x: 0, y: 6)
    }
}

struct PermissionStatusSnapshot {
    let microphone: PermissionAccessState
    let speechRecognition: PermissionAccessState
    let accessibility: PermissionAccessState
    let notifications: PermissionAccessState
    
    func state(for permission: PermissionKind) -> PermissionAccessState {
        switch permission {
        case .microphone:
            return microphone
        case .speechRecognition:
            return speechRecognition
        case .accessibility:
            return accessibility
        case .notifications:
            return notifications
        }
    }
    
    static let placeholder = PermissionStatusSnapshot(
        microphone: .review,
        speechRecognition: .review,
        accessibility: .review,
        notifications: .review
    )
    
    static func capture() async -> PermissionStatusSnapshot {
        let microphone: PermissionAccessState = switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .allowed
        case .notDetermined: .review
        case .denied, .restricted: .denied
        @unknown default: .review
        }
        
        let speechRecognition: PermissionAccessState = switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: .allowed
        case .notDetermined: .review
        case .denied, .restricted: .denied
        @unknown default: .review
        }
        
        let accessibility: PermissionAccessState = AXIsProcessTrusted() ? .allowed : .denied
        
        let notificationSettings = await UNUserNotificationCenter.current().notificationSettings()
        let notifications: PermissionAccessState = switch notificationSettings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: .allowed
        case .notDetermined: .review
        case .denied: .denied
        @unknown default: .review
        }
        
        return PermissionStatusSnapshot(
            microphone: microphone,
            speechRecognition: speechRecognition,
            accessibility: accessibility,
            notifications: notifications
        )
    }
}

enum PermissionAccessState {
    case allowed
    case denied
    case review
    
    var actionTitle: String {
        switch self {
        case .allowed:
            return L10n.Settings.statusReview
        case .denied, .review:
            return L10n.Settings.permissionGrant
        }
    }
    
    var badgeTitle: String {
        switch self {
        case .allowed:
            return L10n.Settings.permissionAllowed
        case .denied:
            return L10n.Settings.permissionNeedsAccess
        case .review:
            return L10n.Settings.statusReview
        }
    }
    
    var badgeTone: ServerStatusCapsule.Tone {
        switch self {
        case .allowed:
            return .active
        case .denied:
            return .neutral
        case .review:
            return .soft
        }
    }
}

struct ServerStatusCapsule: View {
    enum Tone {
        case active
        case success
        case warning
        case soft
        case neutral
    }
    
    let title: String
    let tone: Tone
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Text(title)
            .font(DS.font.mono(size: 11, weight: .medium))
            .tracking(0.16)
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(background)
            .overlay(
                Capsule()
                    .strokeBorder(border, lineWidth: 0.9)
            )
            .clipShape(Capsule())
    }
    
    private var foreground: Color {
        switch tone {
        case .active:
            return colorScheme == .dark ? DS.color.foregroundDark : DS.color.accent
        case .success:
            return colorScheme == .dark ? DS.color.successDark : DS.color.success
        case .warning:
            return colorScheme == .dark ? DS.color.warningDark : DS.color.warning
        case .soft:
            return colorScheme == .dark ? DS.color.foregroundDark : DS.color.foreground
        case .neutral:
            return colorScheme == .dark ? DS.color.mutedDark.opacity(0.96) : DS.color.soft
        }
    }
    
    private var background: Color {
        switch tone {
        case .active:
            return colorScheme == .dark ? DS.color.accentDark.opacity(0.24) : DS.color.accent.opacity(0.12)
        case .success:
            return colorScheme == .dark ? DS.color.successDark.opacity(0.18) : DS.color.success.opacity(0.08)
        case .warning:
            return colorScheme == .dark ? DS.color.warningDark.opacity(0.16) : DS.color.warning.opacity(0.08)
        case .soft:
            return colorScheme == .dark ? DS.color.surface2Dark.opacity(0.96) : Color.white.opacity(0.92)
        case .neutral:
            return colorScheme == .dark ? DS.color.surface3Dark.opacity(0.84) : DS.color.surface.opacity(0.92)
        }
    }
    
    private var border: Color {
        switch tone {
        case .active:
            return colorScheme == .dark ? DS.color.accentDark.opacity(0.48) : DS.color.accent.opacity(0.24)
        case .success:
            return colorScheme == .dark ? DS.color.successDark.opacity(0.38) : DS.color.success.opacity(0.24)
        case .warning:
            return colorScheme == .dark ? DS.color.warningDark.opacity(0.38) : DS.color.warning.opacity(0.24)
        case .soft:
            return colorScheme == .dark ? DS.color.borderDarkSoft.opacity(0.48) : DS.color.borderSoft.opacity(0.54)
        case .neutral:
            return colorScheme == .dark ? DS.color.borderDark.opacity(0.42) : DS.color.borderSoft.opacity(0.42)
        }
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 8)
            
            VStack(spacing: 0) {
                content
            }
            .background(SettingsCardBackground())
        }
    }
}

struct SettingsRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: SettingsTokens.Spacing.content) {
            Text(label)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(colorScheme == .dark ? DS.color.foregroundDark : DS.color.foreground)
            
            Spacer()
            
            content
        }
        .padding(.horizontal, SettingsTokens.Padding.sectionHorizontal)
        .frame(height: SettingsTokens.Size.rowHeight)
    }
}

struct SettingsFormRow<Content: View>: View {
    let label: String
    var helpText: String? = nil
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: SettingsTokens.Spacing.card) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(colorScheme == .dark ? DS.color.foregroundDark : DS.color.foreground)
                if let helpText {
                    SettingsHelpButton(text: helpText)
                }
            }
            .frame(width: SettingsTokens.Width.formLabel, alignment: .leading)
            
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, SettingsTokens.Padding.sectionHorizontal)
        .frame(height: SettingsTokens.Size.rowHeight)
    }
}

struct SettingsHelpButton: View {
    let text: String
    @State private var isPresented = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            Button {
                isPresented.toggle()
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .offset(y: -2)
            
            if isPresented {
                VStack(alignment: .leading, spacing: 0) {
                    Text(text)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(colorScheme == .dark ? DS.color.foregroundDark : DS.color.foreground)
                        .frame(width: SettingsTokens.Size.helpPopoverWidth, alignment: .leading)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(colorScheme == .dark ? DS.color.surface2Dark : Color.white)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.08) : DS.color.borderSoft.opacity(0.6), lineWidth: 1)
                                )
                                .shadow(color: colorScheme == .dark ? .clear : DS.shadow.main.opacity(0.16), radius: 16, x: 0, y: 6)
                        )
                    
                    Triangle()
                        .fill(colorScheme == .dark ? DS.color.surface2Dark : Color.white)
                        .frame(width: 14, height: 10)
                        .overlay(
                            Triangle()
                                .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : DS.color.borderSoft.opacity(0.6), lineWidth: 1)
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 6)
                        .offset(y: -1)
                }
                .offset(x: -10, y: -126)
                .zIndex(1)
            }
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

struct SettingsDivider: View {
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Divider()
            .padding(.leading, SettingsTokens.Padding.sectionHorizontal)
            .overlay(colorScheme == .dark ? Color.white.opacity(0.08) : Color.clear)
    }
}

struct SettingsCardBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        RoundedRectangle(cornerRadius: DS.radius.card, style: .continuous)
            .fill(cardBackground)
            .shadow(
                color: colorScheme == .dark ? .black.opacity(0.0) : DS.shadow.main.opacity(0.14),
                radius: 18,
                x: 0,
                y: 6
            )
            .overlay {
                RoundedRectangle(cornerRadius: DS.radius.card, style: .continuous)
                    .strokeBorder(cardBorderColor, lineWidth: 1)
            }
    }
    
    private var cardBackground: Color {
        colorScheme == .dark ? DS.color.cardBgDark : Color.white.opacity(0.98)
    }
    
    private var cardBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : DS.color.borderSoft.opacity(0.6)
    }
}
