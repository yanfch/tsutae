import SwiftUI

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
