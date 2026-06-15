import SwiftUI

struct SettingsFeatureToggleRow<Trailing: View>: View {
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
                    .toggleStyle(SettingsFeatureSwitchToggleStyle())
                trailing
            }
        }
    }
}

struct SettingsFeatureSwitchToggleStyle: ToggleStyle {
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

struct SettingsCircularIconButtonStyle: ButtonStyle {
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

struct TTSMultilineFormRow<Content: View>: View {
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

struct SettingsInlineTextField: View {
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

struct SettingsInlineMultilineTextField: View {
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

struct SettingsInlineSecureField: View {
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

