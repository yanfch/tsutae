import SwiftUI
import TsutaeCore

private enum STTSettingsScreen {
    case overview
    case localModels
}

private struct LocalModelDialog: Identifiable {
    enum Kind {
        case confirmDelete(LocalSTTModelDescriptor)
        case error(String)
    }
    
    let id = UUID()
    let kind: Kind
}

struct STTSettingsPage: View {
    @ObservedObject var store: STTSettingsStore
    @ObservedObject private var residencyCoordinator = LocalSTTResidencyCoordinator.shared
    @State private var screen: STTSettingsScreen = .overview
    @State private var isRemoteConfigExpanded = false
    @State private var remoteDraftBaseURL = ""
    @State private var remoteDraftModel = ""
    @State private var remoteDraftRequestStyle = Config.STTRemoteRequestStyle.audioTranscriptions.rawValue
    @State private var remoteDraftAPIKey = ""
    @State private var isRemoteAPIKeyRevealed = false
    @State private var initialRemoteDraftSignature = ""
    @State private var lastSuccessfulRemoteTestSignature: String?
    @State private var remoteSavedDismissTask: Task<Void, Never>?
    @State private var localModelDialog: LocalModelDialog?
    
    var body: some View {
        Group {
            switch screen {
            case .overview:
                overviewContent
            case .localModels:
                localModelsContent
            }
        }
        .onAppear {
            isRemoteConfigExpanded = false
            syncRemoteDraftFromStore()
        }
        .alert(item: $localModelDialog) { dialog in
            switch dialog.kind {
            case .confirmDelete(let descriptor):
                return Alert(
                    title: Text(deleteAlertTitle(for: descriptor)),
                    message: Text(deleteAlertMessage(for: descriptor)),
                    primaryButton: .destructive(Text(deleteAlertPrimaryActionTitle(for: descriptor))) {
                        Task {
                            await confirmDeleteModel(descriptor.id)
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
    }
    
    private var overviewContent: some View {
        VStack(alignment: .leading, spacing: SettingsTokens.Spacing.card) {
            SettingsDashboardCard(title: L10n.Settings.sttCurrentSetupTitle, subtitle: L10n.Settings.sttCurrentSetupSubtitle) {
                VStack(alignment: .leading, spacing: SettingsTokens.Spacing.content) {
                    if store.config.stt.mode == .localFirst {
                        SettingsCompactInfoRow(label: L10n.Settings.sttCurrentLocalModelLabel, value: store.selectedModelTitle)
                    } else if store.config.stt.remote.enabled {
                        SettingsCompactInfoRow(label: L10n.Settings.sttCurrentRemoteModelLabel, value: store.config.stt.remote.model ?? L10n.Settings.sttNotSetFallback)
                    }
                    
                    SettingsDivider()
                    
                    STTStackedControlRow(label: L10n.Settings.sttModeLabel) {
                        SettingsDropdown(
                            selection: store.modeBinding,
                            options: [
                                .init(id: Config.STTRoutingMode.localFirst.rawValue, title: L10n.Settings.sttModeLocalFirst),
                                .init(id: Config.STTRoutingMode.remoteFirst.rawValue, title: L10n.Settings.sttModeRemoteFirst, isDisabled: store.isRemoteConfigured == false)
                            ],
                            tone: .active,
                            width: SettingsTokens.Width.modeDropdown
                        )
                    }
                    
                    STTStackedControlRow(label: L10n.Settings.sttLanguageLabel) {
                        SettingsDropdown(
                            selection: store.languageBinding,
                            options: [
                                .init(id: "auto", title: L10n.Settings.sttLanguageAutoDetectLong),
                                .init(id: "zh", title: L10n.Settings.languageChinese),
                                .init(id: "en", title: L10n.Settings.languageEnglish)
                            ],
                            tone: .soft,
                            width: SettingsTokens.Width.languageDropdown
                        )
                    }
                }
            }
            
            SettingsDashboardCard(title: L10n.Settings.sttLocalSectionTitle, subtitle: L10n.Settings.sttLocalSectionSubtitle) {
                VStack(alignment: .leading, spacing: SettingsTokens.Spacing.content) {
                    HStack(spacing: 8) {
                        ServerStatusCapsule(title: store.selectedModelTitle, tone: .active)
                        ServerStatusCapsule(title: L10n.Settings.sttDownloadedCount(store.downloadedCount), tone: .soft)
                    }
                    
                    SettingsKeyValueList(rows: [
                        (L10n.Settings.sttSelectedModelLabel, store.selectedModelTitle),
                        (L10n.Settings.sttLibraryLabel, L10n.Settings.sttCuratedModelsCount(store.availableModelCount)),
                        (L10n.Settings.sttDownloadedLabel, L10n.Settings.sttReadyOnThisMacCount(store.downloadedCount)),
                        (L10n.Settings.sttNextStepLabel, L10n.Settings.sttManageModelsValue)
                    ])
                    
                    HStack(spacing: 10) {
                        Button(L10n.Settings.sttManageModelsButton) {
                            store.prepareLocalModelsPresentation()
                            withAnimation(.easeInOut(duration: 0.18)) {
                                screen = .localModels
                            }
                        }
                        .buttonStyle(SettingsAccentButtonStyle())
                        
                        Button(L10n.Settings.sttRefreshButton) {
                            store.refreshDiskState()
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    SettingsToggleRow(
                        title: L10n.Settings.sttKeepLocalWarmedTitle,
                        subtitle: L10n.Settings.sttKeepLocalWarmedSubtitle,
                        isOn: store.keepLocalWarmedInRemoteFirstBinding,
                        badgeTitle: store.keepLocalWarmedInRemoteFirstBadgeTitle,
                        badgeTone: store.config.stt.local.keepModelWarmedInRemoteFirst ? .active : .neutral
                    )
                    
                    if residencyCoordinator.warmingModelID == store.selectedModelID {
                        SettingsInlineStatusMessage(
                            text: L10n.Settings.sttWarmingModel(store.selectedModelTitle),
                            tone: .info
                        )
                    }
                }
            }
            
            SettingsDashboardCard(title: L10n.Settings.sttRemoteSectionTitle, subtitle: L10n.Settings.sttRemoteSectionSubtitle) {
                VStack(alignment: .leading, spacing: SettingsTokens.Spacing.content) {
                    SettingsToggleRow(
                        title: L10n.Settings.sttRemoteUseTitle,
                        subtitle: store.config.stt.remote.enabled ? L10n.Settings.sttRemoteUseEnabledSubtitle : L10n.Settings.sttRemoteUseDisabledSubtitle,
                        isOn: remoteEnabledBinding,
                        badgeTitle: store.remoteSummaryTitle,
                        badgeTone: store.config.stt.remote.enabled ? .active : .neutral,
                        trailing: {
                            if store.config.stt.remote.enabled {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        isRemoteConfigExpanded.toggle()
                                    }
                                } label: {
                                    Image(systemName: isRemoteConfigExpanded ? "chevron.up" : "chevron.down")
                                }
                                .buttonStyle(SettingsIconButtonStyle())
                            }
                        }
                    )
                    
                    if store.config.stt.remote.enabled && isRemoteConfigExpanded {
                        SettingsSection(title: L10n.Settings.sttRemoteConnectionTitle) {
                            SettingsFormRow(label: L10n.Settings.sttRemoteProtocolLabel, helpText: remoteProtocolHelpText) {
                                SettingsDropdown(
                                    selection: $remoteDraftRequestStyle,
                                    options: [
                                        .init(id: Config.STTRemoteRequestStyle.audioTranscriptions.rawValue, title: L10n.Settings.sttRemoteProtocolTranscriptions),
                                        .init(id: Config.STTRemoteRequestStyle.chatCompletionsAudio.rawValue, title: L10n.Settings.sttRemoteProtocolChatAudio)
                                    ],
                                    tone: .soft,
                                    width: SettingsTokens.Size.remoteFieldWidth,
                                    menuWidth: SettingsTokens.Width.remoteProtocolMenu
                                )
                            }
                            SettingsDivider()
                            SettingsFormRow(label: L10n.Settings.sttRemoteBaseURLLabel) {
                                SettingsTextInputField(
                                    text: $remoteDraftBaseURL,
                                    placeholder: remoteBaseURLPlaceholder,
                                    width: SettingsTokens.Size.remoteFieldWidth
                                )
                            }
                            SettingsDivider()
                            SettingsFormRow(label: L10n.Settings.sttRemoteModelLabel) {
                                SettingsTextInputField(
                                    text: $remoteDraftModel,
                                    placeholder: remoteModelPlaceholder,
                                    width: SettingsTokens.Size.remoteFieldWidth
                                )
                            }
                            SettingsDivider()
                            SettingsFormRow(label: L10n.Settings.sttRemoteAPIKeyLabel, helpText: remoteAPIKeyHelpText) {
                                SettingsSecureRevealField(
                                    text: $remoteDraftAPIKey,
                                    isRevealed: $isRemoteAPIKeyRevealed,
                                    placeholder: remoteAPIKeyPlaceholder,
                                    width: SettingsTokens.Size.remoteFieldWidth,
                                    onReveal: {
                                        if remoteDraftAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                            remoteDraftAPIKey = store.loadRemoteAPIKey() ?? ""
                                        }
                                    }
                                )
                            }
                        }
                        
                        HStack(alignment: .center, spacing: 12) {
                            if shouldShowRemoteStatus {
                                SettingsInlineStatusMessage(
                                    text: remoteFeedbackText,
                                    tone: remoteFeedbackTone
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                Spacer(minLength: 0)
                            }
                            
                            HStack(spacing: 12) {
                                Button(store.remoteCheckState.isChecking ? L10n.Settings.sttRemoteCheckingButton : L10n.Settings.sttRemoteTestButton) {
                                    testRemoteDraft()
                                }
                                .buttonStyle(.bordered)
                                .disabled(canTestRemoteDraft == false)
                                
                                Button(L10n.Settings.sttRemoteSaveButton) {
                                    saveRemoteDraft()
                                }
                                .buttonStyle(SettingsAccentButtonStyle())
                                .disabled(canSaveRemoteDraft == false)
                            }
                        }
                    }
                }
            }
            
            SettingsDashboardCard(title: L10n.Settings.sttFallbackSectionTitle, subtitle: L10n.Settings.sttFallbackSectionSubtitle) {
                SettingsToggleRow(
                    title: L10n.Settings.sttFallbackAppleSpeechTitle,
                    subtitle: L10n.Settings.sttFallbackAppleSpeechSubtitle,
                    isOn: store.fallbackEnabledBinding,
                    badgeTitle: store.fallbackBadgeTitle,
                    badgeTone: store.config.stt.fallbackEngine == nil ? .neutral : .active
                )
            }
        }
    }
    
    private var localModelsContent: some View {
        VStack(alignment: .leading, spacing: SettingsTokens.Spacing.card) {
            HStack(spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        screen = .overview
                    }
                } label: {
                    Label(L10n.Settings.sttBackToSTT, systemImage: "chevron.left")
                }
                .buttonStyle(SettingsGhostButtonStyle())
                
                Spacer(minLength: 0)
                
                ServerStatusCapsule(title: L10n.Settings.sttDownloadedCount(store.downloadedCount), tone: .soft)
                ServerStatusCapsule(title: store.selectedModelTitle, tone: .active)
            }
            
            SettingsDashboardCard(title: L10n.Settings.sttLocalModelsTitle, subtitle: L10n.Settings.sttLocalModelsSubtitle) {
                VStack(alignment: .leading, spacing: SettingsTokens.Spacing.content) {
                    SettingsKeyValueList(rows: [
                        (L10n.Settings.sttSelectedLabel, store.selectedModelTitle),
                        (L10n.Settings.sttAvailableLabel, L10n.Settings.sttCuratedModelsCount(store.availableModelCount)),
                        (L10n.Settings.sttDownloadedLabel, L10n.Settings.sttReadyCount(store.downloadedCount)),
                        (L10n.Settings.sttPrimaryModeLabel, store.modeTitle)
                    ])
                    
                    HStack(spacing: 10) {
                        SettingsSearchField(text: $store.searchQuery)
                        
                        SettingsDropdown(
                            selection: store.filterBinding,
                            options: LocalSTTModelFilter.allCases.map { filter in
                                .init(id: filter.rawValue, title: filter.title)
                            },
                            tone: .soft,
                            width: SettingsTokens.Width.modelFilterDropdown
                        )
                        
                        Button(L10n.Settings.sttRefreshButton) {
                            store.refreshDiskState()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            
            SettingsDashboardCard(title: L10n.Settings.sttModelLibraryTitle, subtitle: L10n.Settings.sttModelLibrarySubtitle) {
                SettingsTwoColumnGrid {
                    ForEach(store.filteredModels) { descriptor in
                        STTLocalModelCard(
                            descriptor: descriptor,
                            state: store.downloadState(for: descriptor.id),
                            isSelected: store.selectedModelID == descriptor.id,
                            isWarming: residencyCoordinator.warmingModelID == descriptor.id,
                            onDownload: { store.downloadModel(descriptor.id) },
                            onSelect: { store.selectModel(descriptor.id) },
                            onDelete: store.canDeleteModel(descriptor.id) ? {
                                promptDeleteModel(descriptor.id)
                            } : nil
                        )
                    }
                }
            }
        }
    }
    
    private func promptDeleteModel(_ modelID: String) {
        guard let descriptor = LocalSTTModelCatalog.descriptor(id: modelID) else { return }
        localModelDialog = .init(kind: .confirmDelete(descriptor))
    }
    
    private func confirmDeleteModel(_ modelID: String) async {
        do {
            try await store.deleteModel(modelID)
        } catch {
            localModelDialog = .init(kind: .error(error.localizedDescription))
        }
    }
    
    private func deleteAlertTitle(for descriptor: LocalSTTModelDescriptor) -> String {
        store.selectedModelID == descriptor.id ? L10n.Settings.sttDeleteCurrentTitle : L10n.Settings.sttDeleteDownloadedTitle
    }
    
    private func deleteAlertPrimaryActionTitle(for descriptor: LocalSTTModelDescriptor) -> String {
        store.selectedModelID == descriptor.id ? L10n.Settings.sttDeleteAndSwitchAction : L10n.Settings.sttDeleteAction
    }
    
    private func deleteAlertMessage(for descriptor: LocalSTTModelDescriptor) -> String {
        if store.selectedModelID == descriptor.id {
            let fallbackTitle = store.replacementModelTitle(afterDeleting: descriptor.id)
            return L10n.Settings.sttDeleteCurrentMessage(modelName: descriptor.displayName, replacementName: fallbackTitle)
        }
        return L10n.Settings.sttDeleteDownloadedMessage(descriptor.displayName)
    }
    
    private var remoteEnabledBinding: Binding<Bool> {
        Binding(
            get: { store.config.stt.remote.enabled },
            set: { newValue in
                if newValue {
                    syncRemoteDraftFromStore()
                }
                store.setRemoteEnabled(newValue)
                withAnimation(.easeInOut(duration: 0.18)) {
                    isRemoteConfigExpanded = newValue
                }
            }
        )
    }
    
    private var remoteDraftSignature: String {
        [remoteDraftBaseURL, remoteDraftModel, remoteDraftRequestStyle, remoteDraftAPIKey]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: "|")
    }
    
    private var canTestRemoteDraft: Bool {
        store.remoteCheckState.isChecking == false
            && remoteDraftBaseURL.nilIfBlank != nil
            && remoteDraftModel.nilIfBlank != nil
    }
    
    private var canSaveRemoteDraft: Bool {
        store.remoteCheckState.isChecking == false
            && remoteDraftBaseURL.nilIfBlank != nil
            && remoteDraftModel.nilIfBlank != nil
            && lastSuccessfulRemoteTestSignature == remoteDraftSignature
    }
    
    private var hasRemoteDraftChanges: Bool {
        remoteDraftSignature != initialRemoteDraftSignature
    }
    
    private var remoteBaseURLPlaceholder: String {
        L10n.Settings.sttRemoteBaseURLPlaceholder
    }
    
    private var remoteModelPlaceholder: String {
        L10n.Settings.sttRemoteModelPlaceholder
    }
    
    private var remoteAPIKeyPlaceholder: String {
        store.hasStoredRemoteAPIKey ? L10n.Settings.sttRemoteAPIKeyStoredPlaceholder : "sk-…"
    }
    
    private var remoteAPIKeyHelpText: String {
        L10n.Settings.sttRemoteAPIKeyHelp
    }
    
    private var remoteProtocolHelpText: String {
        switch Config.STTRemoteRequestStyle(rawValue: remoteDraftRequestStyle) ?? .audioTranscriptions {
        case .audioTranscriptions:
            return L10n.Settings.sttRemoteProtocolHelpTranscriptions
        case .chatCompletionsAudio:
            return L10n.Settings.sttRemoteProtocolHelpChatAudio
        }
    }
    
    private var shouldShowRemoteStatus: Bool {
        store.config.stt.remote.enabled
    }
    
    private var remoteFeedbackText: String {
        if hasRemoteDraftChanges {
            if lastSuccessfulRemoteTestSignature == remoteDraftSignature {
                return L10n.Settings.sttRemoteFeedbackTestPassed
            }
            if store.remoteCheckState.isError {
                return localizedRemoteCheckState(store.remoteCheckState)
            }
            return store.remoteCheckState.isChecking ? L10n.Settings.sttRemoteFeedbackChecking : L10n.Settings.sttRemoteFeedbackEdited
        }
        
        switch store.remoteCheckState {
        case .notTested:
            return store.isRemoteConfigured ? L10n.Settings.sttRemoteFeedbackSavedConfiguration : L10n.Settings.sttRemoteFeedbackNotTested
        case .checking:
            return L10n.Settings.sttRemoteFeedbackChecking
        case .saved:
            return L10n.Settings.sttRemoteFeedbackSaved
        case .savedConfiguration:
            return L10n.Settings.sttRemoteFeedbackSavedConfiguration
        case .invalidBaseURL, .missingModel, .transcriptionSucceeded(_), .failed(_):
            return localizedRemoteCheckState(store.remoteCheckState)
        }
    }
    
    private var remoteFeedbackTone: SettingsInlineStatusMessage.Tone {
        if hasRemoteDraftChanges {
            if lastSuccessfulRemoteTestSignature == remoteDraftSignature {
                return .success
            }
            if store.remoteCheckState.isError {
                return .danger
            }
            return store.remoteCheckState.isChecking ? .info : .neutral
        }
        
        switch store.remoteCheckState {
        case .notTested, .savedConfiguration:
            return .neutral
        case .checking:
            return .info
        case .saved, .transcriptionSucceeded(_):
            return .success
        case .invalidBaseURL, .missingModel, .failed(_):
            return .danger
        }
    }
    
    private func localizedRemoteCheckState(_ state: RemoteCheckState) -> String {
        switch state {
        case .notTested:
            return L10n.Settings.sttRemoteFeedbackNotTested
        case .checking:
            return L10n.Settings.sttRemoteFeedbackChecking
        case .saved:
            return L10n.Settings.sttRemoteFeedbackSaved
        case .savedConfiguration:
            return L10n.Settings.sttRemoteFeedbackSavedConfiguration
        case .invalidBaseURL:
            return L10n.Settings.sttRemoteErrorInvalidBaseURL
        case .missingModel:
            return L10n.Settings.sttRemoteErrorModelRequired
        case .transcriptionSucceeded(let text):
            if let text, text.isEmpty == false {
                return L10n.Settings.sttRemoteTranscriptionOKWithText(text)
            }
            return L10n.Settings.sttRemoteTranscriptionOK
        case .failed(let message):
            return message
        }
    }
    
    private func syncRemoteDraftFromStore() {
        remoteSavedDismissTask?.cancel()
        let baseURL = store.config.stt.remote.baseURL ?? ""
        let model = store.config.stt.remote.model ?? ""
        let requestStyle = store.config.stt.remote.requestStyle.rawValue
        remoteDraftBaseURL = baseURL
        remoteDraftModel = model
        remoteDraftRequestStyle = requestStyle
        remoteDraftAPIKey = ""
        initialRemoteDraftSignature = [baseURL, model, requestStyle, ""]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: "|")
        lastSuccessfulRemoteTestSignature = nil
        store.resetRemoteCheckState()
    }
    
    private func testRemoteDraft() {
        remoteSavedDismissTask?.cancel()
        store.checkRemoteEndpoint(
            baseURL: remoteDraftBaseURL,
            model: remoteDraftModel,
            requestStyleRawValue: remoteDraftRequestStyle,
            apiKey: store.resolvedRemoteAPIKey(draft: remoteDraftAPIKey)
        ) { success in
            lastSuccessfulRemoteTestSignature = success ? remoteDraftSignature : nil
        }
    }
    
    private func saveRemoteDraft() {
        remoteSavedDismissTask?.cancel()
        do {
            try store.saveRemoteSettings(
                baseURL: remoteDraftBaseURL,
                model: remoteDraftModel,
                requestStyleRawValue: remoteDraftRequestStyle,
                apiKey: store.resolvedRemoteAPIKey(draft: remoteDraftAPIKey)
            )
            initialRemoteDraftSignature = remoteDraftSignature
            lastSuccessfulRemoteTestSignature = remoteDraftSignature
            store.remoteCheckState = .saved
            remoteSavedDismissTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.6))
                guard Task.isCancelled == false else { return }
                guard hasRemoteDraftChanges == false else { return }
                if store.remoteCheckState == .saved {
                    store.remoteCheckState = .savedConfiguration
                }
            }
        } catch {
            store.remoteCheckState = .failed(error.localizedDescription)
        }
    }
}


private struct STTStackedControlRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            content
        }
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

private struct SettingsCompactInfoRow: View {
    let label: String
    let value: String
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(DS.font.mono(size: 12, weight: .regular))
                .foregroundStyle(colorScheme == .dark ? DS.color.foregroundDark : DS.color.foreground)
        }
    }
}

private struct SettingsTextInputField: View {
    @Binding var text: String
    let placeholder: String
    var width: CGFloat = 420
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .padding(.horizontal, SettingsTokens.Padding.sidebarHorizontal)
            .frame(width: width, height: SettingsTokens.Size.controlHeight)
            .background(background)
    }
    
    private var background: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(colorScheme == .dark ? DS.color.surface2Dark.opacity(0.92) : Color.white.opacity(0.96))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(colorScheme == .dark ? DS.color.borderDarkSoft.opacity(0.45) : DS.color.borderSoft.opacity(0.6), lineWidth: 1)
            )
    }
}

private struct SettingsSecureRevealField: View {
    @Binding var text: String
    @Binding var isRevealed: Bool
    let placeholder: String
    var width: CGFloat = 420
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
            
            Button {
                let nextValue = !isRevealed
                if nextValue {
                    onReveal?()
                }
                isRevealed = nextValue
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DS.color.accent)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, SettingsTokens.Padding.sidebarHorizontal)
        .frame(width: width, height: SettingsTokens.Size.controlHeight)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(colorScheme == .dark ? DS.color.surface2Dark.opacity(0.92) : Color.white.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(colorScheme == .dark ? DS.color.borderDarkSoft.opacity(0.45) : DS.color.borderSoft.opacity(0.6), lineWidth: 1)
                )
        )
    }
}

private struct SettingsInlineStatusMessage: View {
    enum Tone {
        case neutral
        case info
        case success
        case danger
    }
    
    let text: String
    let tone: Tone
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(background)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(border, lineWidth: 1)
                )
        )
    }
    
    private var iconName: String {
        switch tone {
        case .neutral:
            return "info.circle"
        case .info:
            return "clock"
        case .success:
            return "checkmark.circle"
        case .danger:
            return "exclamationmark.triangle"
        }
    }
    
    private var foreground: Color {
        switch tone {
        case .neutral:
            return colorScheme == .dark ? DS.color.mutedDark : DS.color.soft
        case .info:
            return colorScheme == .dark ? DS.color.foregroundDark : DS.color.foreground
        case .success:
            return colorScheme == .dark ? DS.color.successDark : DS.color.success
        case .danger:
            return colorScheme == .dark ? DS.color.dangerDark : DS.color.danger
        }
    }
    
    private var background: Color {
        switch tone {
        case .neutral:
            return colorScheme == .dark ? DS.color.surface2Dark.opacity(0.9) : DS.color.surface.opacity(0.95)
        case .info:
            return colorScheme == .dark ? DS.color.surface2Dark.opacity(0.95) : Color.white.opacity(0.95)
        case .success:
            return colorScheme == .dark ? DS.color.successDark.opacity(0.14) : DS.color.success.opacity(0.08)
        case .danger:
            return colorScheme == .dark ? DS.color.dangerDark.opacity(0.14) : DS.color.danger.opacity(0.08)
        }
    }
    
    private var border: Color {
        switch tone {
        case .neutral:
            return colorScheme == .dark ? DS.color.borderDarkSoft.opacity(0.36) : DS.color.borderSoft.opacity(0.52)
        case .info:
            return colorScheme == .dark ? DS.color.borderDarkSoft.opacity(0.42) : DS.color.borderSoft.opacity(0.58)
        case .success:
            return colorScheme == .dark ? DS.color.successDark.opacity(0.34) : DS.color.success.opacity(0.26)
        case .danger:
            return colorScheme == .dark ? DS.color.dangerDark.opacity(0.34) : DS.color.danger.opacity(0.26)
        }
    }
}

private struct SettingsSwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(configuration.isOn ? DS.color.accent : DS.color.borderSoft.opacity(0.8))
                .frame(width: SettingsTokens.Size.toggleTrackWidth, height: SettingsTokens.Size.toggleTrackHeight)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: SettingsTokens.Size.toggleThumb, height: SettingsTokens.Size.toggleThumb)
                        .padding(3)
                        .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 1)
                }
                .animation(.easeInOut(duration: 0.16), value: configuration.isOn)
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsSearchField: View {
    @Binding var text: String
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(L10n.Settings.sttSearchModelsPlaceholder, text: $text)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, SettingsTokens.Padding.sidebarHorizontal)
        .frame(width: SettingsTokens.Size.searchFieldWidth, height: SettingsTokens.Size.controlHeight)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(colorScheme == .dark ? DS.color.surface2Dark.opacity(0.92) : Color.white.opacity(0.88))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(colorScheme == .dark ? DS.color.borderDarkSoft.opacity(0.45) : DS.color.borderSoft.opacity(0.52), lineWidth: 1)
                )
        )
    }
}

private struct STTLocalModelCard: View {
    let descriptor: LocalSTTModelDescriptor
    let state: STTDownloadState
    let isSelected: Bool
    let isWarming: Bool
    let onDownload: () -> Void
    let onSelect: () -> Void
    let onDelete: (() -> Void)?
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
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
                    
                    ModelStateBadge(title: stateBadgeTitle, tone: stateBadgeTone, icon: stateBadgeIcon)
                }
                
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        SettingsMetricPill(title: descriptor.runtime)
                        SettingsMetricPill(title: descriptor.size)
                        SettingsMetricPill(title: descriptor.memory)
                    }
                    
                    FlowLayout(spacing: 8, lineSpacing: 8) {
                        SettingsFeatureTag(title: groupBadgeTitle, tone: .group)
                        if descriptor.isRecommended {
                            SettingsFeatureTag(title: L10n.Settings.sttModelTopPick, tone: .accent)
                        }
                        ForEach(descriptor.tags, id: \.self) { tag in
                            SettingsFeatureTag(title: localizedTag(tag), tone: tag == "Beta" ? .neutral : .plain)
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
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .layoutPriority(1)
                        Spacer(minLength: 12)
                        actionView
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    
                    if case .downloading(let progress) = state {
                        STTInlineDownloadProgress(progress: progress)
                    }
                }
            }
            .padding(SettingsTokens.Padding.localModelCard)
            .frame(maxWidth: .infinity, minHeight: 244, alignment: .leading)
        }
        .background(cardBackground)
        .overlay(cardBorder)
        .shadow(color: cardShadowColor, radius: 18, x: 0, y: 10)
    }
    
    private var statusText: String {
        if isWarming {
            return L10n.Settings.sttModelStatusWarmingLocal
        }
        switch state {
        case .notStarted:
            return L10n.Settings.sttModelStatusNotDownloaded
        case .downloading:
            return L10n.Settings.sttModelStatusPreparingFiles
        case .downloaded:
            return isSelected ? L10n.Settings.sttModelStatusDefaultLocalModel : L10n.Settings.sttModelStatusReady
        case .failed:
            return L10n.Settings.sttModelStatusRetryDownload
        }
    }
    
    private var localizedSummary: String {
        switch descriptor.id {
        case "sensevoice-small":
            return L10n.Settings.sttModelSummarySenseVoiceSmall
        case "qwen3-asr-int8":
            return L10n.Settings.sttModelSummaryQwen3ASRInt8
        case "paraformer-large-zh":
            return L10n.Settings.sttModelSummaryParaformerLargeZH
        case "parakeet-ctc-zh-cn":
            return L10n.Settings.sttModelSummaryParakeetCTCChinese
        case "parakeet-tdt-v3":
            return L10n.Settings.sttModelSummaryParakeetTDTV3
        case "parakeet-eou":
            return L10n.Settings.sttModelSummaryParakeetEOU
        default:
            return descriptor.summary
        }
    }
    
    private func localizedTag(_ tag: String) -> String {
        switch tag {
        case "Best for Mixed":
            return L10n.Settings.sttModelTagBestForMixed
        case "Balanced":
            return L10n.Settings.sttModelTagBalanced
        case "Low Memory":
            return L10n.Settings.sttModelTagLowMemory
        case "Mixed Language":
            return L10n.Settings.sttModelTagMixedLanguage
        case "Higher Memory":
            return L10n.Settings.sttModelTagHigherMemory
        case "Slower":
            return L10n.Settings.sttModelTagSlower
        case "Best for Chinese":
            return L10n.Settings.sttModelTagBestForChinese
        case "Chinese Focused":
            return L10n.Settings.sttModelTagChineseFocused
        case "Chinese":
            return L10n.Settings.sttModelTagChineseOnly
        case "Spacing Issues":
            return L10n.Settings.sttModelTagSpacingIssues
        case "Best for English":
            return L10n.Settings.sttModelTagBestForEnglish
        case "Fast":
            return L10n.Settings.sttModelTagFast
        case "Preview Only":
            return L10n.Settings.sttModelTagPreviewOnly
        case "Beta":
            return L10n.Settings.sttModelTagBeta
        default:
            return tag
        }
    }
    
    private var groupBadgeTitle: String {
        switch descriptor.group {
        case .auto:
            return L10n.Settings.sttModelGroupMixed
        case .chinese:
            return L10n.Settings.sttModelGroupChinese
        case .english:
            return L10n.Settings.sttModelGroupEnglish
        case .preview:
            return L10n.Settings.sttModelGroupPreview
        }
    }
    
    private var stateBadgeTitle: String {
        if isWarming {
            return L10n.Settings.sttModelBadgeWarming
        }
        if isSelected {
            return L10n.Settings.sttModelBadgeUsing
        }
        switch state {
        case .notStarted:
            return L10n.Settings.sttModelBadgeAvailable
        case .downloading:
            return L10n.Settings.sttModelBadgeDownloading
        case .downloaded:
            return L10n.Settings.sttModelBadgeDownloaded
        case .failed:
            return L10n.Settings.sttModelBadgeRetry
        }
    }
    
    private var stateBadgeTone: ServerStatusCapsule.Tone {
        if isWarming || isSelected {
            return .active
        }
        switch state {
        case .downloaded:
            return .soft
        case .downloading:
            return .active
        case .notStarted, .failed:
            return .neutral
        }
    }
    
    private var stateBadgeIcon: String {
        if isWarming {
            return "clock.fill"
        }
        if isSelected {
            return "checkmark.circle.fill"
        }
        switch state {
        case .notStarted:
            return "arrow.down.circle"
        case .downloading:
            return "arrow.down.circle.fill"
        case .downloaded:
            return "checkmark.circle"
        case .failed:
            return "exclamationmark.triangle"
        }
    }
    
    private var primaryActionTitle: String {
        switch state {
        case .notStarted:
            return L10n.Settings.sttModelActionDownload
        case .downloading:
            return L10n.Settings.sttModelActionDownloading
        case .downloaded:
            return L10n.Settings.sttModelActionSetDefault
        case .failed:
            return L10n.Settings.sttModelActionRetry
        }
    }
    
    private var primaryAction: () -> Void {
        switch state {
        case .downloaded:
            return onSelect
        case .notStarted, .failed, .downloading:
            return onDownload
        }
    }
    
    private var primaryActionDisabled: Bool {
        if case .downloading = state { return true }
        return false
    }
    
    private var primaryActionIsSelect: Bool {
        if case .downloaded = state { return true }
        return false
    }
    
    private var canShowDeleteAction: Bool {
        onDelete != nil && deleteActionDisabled == false
    }
    
    private var deleteActionDisabled: Bool {
        isWarming
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
            .strokeBorder(cardBorderColor, lineWidth: cardBorderWidth)
    }
    
    private var cardBorderColor: Color {
        if isSelected {
            return colorScheme == .dark ? DS.color.accentDark.opacity(0.72) : DS.color.accent.opacity(0.52)
        }
        switch state {
        case .downloading:
            return colorScheme == .dark ? DS.color.accentDark.opacity(0.46) : DS.color.accent.opacity(0.34)
        case .downloaded:
            return colorScheme == .dark ? DS.color.borderDarkSoft.opacity(0.52) : DS.color.border.opacity(0.42)
        case .failed:
            return colorScheme == .dark ? DS.color.warningDark.opacity(0.4) : DS.color.warning.opacity(0.34)
        case .notStarted:
            return colorScheme == .dark ? Color.white.opacity(0.13) : DS.color.borderSoft.opacity(0.86)
        }
    }
    
    private var cardBorderWidth: CGFloat {
        if isSelected { return 2 }
        if case .downloading = state { return 1.5 }
        if case .downloaded = state { return 1.2 }
        return 1
    }
    
    private var cardShadowColor: Color {
        if isSelected {
            return colorScheme == .dark ? DS.color.accentDark.opacity(0.14) : DS.shadow.main
        }
        if case .downloading = state {
            return colorScheme == .dark ? DS.color.accentDark.opacity(0.08) : DS.shadow.main.opacity(0.75)
        }
        return colorScheme == .dark ? Color.black.opacity(0.14) : DS.shadow.soft
    }
    
    @ViewBuilder
    private var actionView: some View {
        if isSelected {
            if let onDelete, canShowDeleteAction {
                Button(role: .destructive, action: onDelete) {
                    Label(L10n.Settings.sttDeleteAction, systemImage: "trash")
                }
                .buttonStyle(SettingsDangerButtonStyle())
                .controlSize(.small)
                .fixedSize(horizontal: true, vertical: false)
            }
        } else if primaryActionIsSelect {
            HStack(spacing: 8) {
                if let onDelete, canShowDeleteAction {
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(SettingsDangerIconButtonStyle())
                    .controlSize(.small)
                }
                Button(primaryActionTitle, action: primaryAction)
                    .buttonStyle(SettingsAccentButtonStyle())
                    .controlSize(.small)
                    .frame(minWidth: 116)
                    .disabled(primaryActionDisabled)
            }
        } else if case .downloading = state {
            Button(primaryActionTitle, action: primaryAction)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(minWidth: 116)
                .disabled(primaryActionDisabled)
        } else {
            Button(primaryActionTitle, action: primaryAction)
                .buttonStyle(SettingsAccentButtonStyle())
                .controlSize(.small)
                .frame(minWidth: 116)
                .disabled(primaryActionDisabled)
        }
    }
    
}

private struct ModelStateBadge: View {
    let title: String
    let tone: ServerStatusCapsule.Tone
    let icon: String
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Label {
            Text(title)
                .font(DS.font.mono(size: 11, weight: .medium))
        } icon: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(background)
        .overlay(
            Capsule()
                .strokeBorder(border, lineWidth: 1)
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
            return colorScheme == .dark ? DS.color.mutedDark : DS.color.soft
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
            return colorScheme == .dark ? DS.color.surface2Dark.opacity(0.94) : Color.white.opacity(0.94)
        case .neutral:
            return colorScheme == .dark ? DS.color.surface3Dark.opacity(0.84) : DS.color.surface.opacity(0.96)
        }
    }
    
    private var border: Color {
        switch tone {
        case .active:
            return colorScheme == .dark ? DS.color.accentDark.opacity(0.42) : DS.color.accent.opacity(0.28)
        case .success:
            return colorScheme == .dark ? DS.color.successDark.opacity(0.38) : DS.color.success.opacity(0.24)
        case .warning:
            return colorScheme == .dark ? DS.color.warningDark.opacity(0.38) : DS.color.warning.opacity(0.24)
        case .soft:
            return colorScheme == .dark ? DS.color.borderDarkSoft.opacity(0.44) : DS.color.borderSoft.opacity(0.56)
        case .neutral:
            return colorScheme == .dark ? DS.color.borderDark.opacity(0.36) : DS.color.borderSoft.opacity(0.48)
        }
    }
}

private struct SettingsMetricPill: View {
    let title: String
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Text(title)
            .font(DS.font.mono(size: 11, weight: .medium))
            .foregroundStyle(colorScheme == .dark ? DS.color.foregroundDark : DS.color.soft)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                Capsule()
                    .fill(colorScheme == .dark ? DS.color.surface3Dark.opacity(0.72) : DS.color.surface.opacity(0.92))
                    .overlay(
                        Capsule()
                            .strokeBorder(colorScheme == .dark ? DS.color.borderDarkSoft.opacity(0.32) : DS.color.borderSoft.opacity(0.48), lineWidth: 1)
                    )
            )
    }
}

private struct SettingsFeatureTag: View {
    enum Tone {
        case group
        case accent
        case plain
        case neutral
    }
    
    let title: String
    let tone: Tone
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Text(title)
            .font(DS.font.mono(size: 10.5, weight: .medium))
            .foregroundStyle(foreground)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(
                Capsule()
                    .fill(background)
                    .overlay(
                        Capsule()
                            .strokeBorder(border, lineWidth: 1)
                    )
            )
    }
    
    private var foreground: Color {
        switch tone {
        case .group:
            return colorScheme == .dark ? DS.color.foregroundDark : DS.color.foreground
        case .accent:
            return colorScheme == .dark ? DS.color.foregroundDark : DS.color.accent
        case .plain:
            return colorScheme == .dark ? DS.color.mutedDark : DS.color.soft
        case .neutral:
            return colorScheme == .dark ? DS.color.warningDark : DS.color.warning
        }
    }
    
    private var background: Color {
        switch tone {
        case .group:
            return colorScheme == .dark ? DS.color.surface3Dark.opacity(0.78) : DS.color.surface2.opacity(0.88)
        case .accent:
            return colorScheme == .dark ? DS.color.accentDark.opacity(0.22) : DS.color.accent.opacity(0.1)
        case .plain:
            return colorScheme == .dark ? DS.color.surface2Dark.opacity(0.92) : Color.white.opacity(0.92)
        case .neutral:
            return colorScheme == .dark ? DS.color.warningDark.opacity(0.16) : DS.color.warning.opacity(0.08)
        }
    }
    
    private var border: Color {
        switch tone {
        case .group:
            return colorScheme == .dark ? DS.color.borderDarkSoft.opacity(0.36) : DS.color.borderSoft.opacity(0.54)
        case .accent:
            return colorScheme == .dark ? DS.color.accentDark.opacity(0.34) : DS.color.accent.opacity(0.24)
        case .plain:
            return colorScheme == .dark ? DS.color.borderDarkSoft.opacity(0.3) : DS.color.borderSoft.opacity(0.46)
        case .neutral:
            return colorScheme == .dark ? DS.color.warningDark.opacity(0.32) : DS.color.warning.opacity(0.22)
        }
    }
}

private struct STTInlineDownloadProgress: View {
    let progress: Double
    @State private var displayedProgress: Double = 0
    
    var body: some View {
        HStack(spacing: 10) {
            STTModelDownloadProgressBar(progress: displayedProgress)
                .frame(height: 8)
            STTAnimatedDownloadProgressLabel(progress: displayedProgress)
                .font(DS.font.mono(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .trailing)
        }
        .onAppear {
            displayedProgress = clamped(progress)
        }
        .onChange(of: progress) { _, newValue in
            let target = clamped(newValue)
            let delta = abs(target - displayedProgress)
            let duration = min(max(0.22, delta * 2.8), 1.8)
            withAnimation(.linear(duration: duration)) {
                displayedProgress = target
            }
        }
    }
    
    private func clamped(_ value: Double) -> Double {
        max(0, min(value, 1))
    }
}

private struct STTAnimatedDownloadProgressLabel: View, Animatable {
    var progress: Double
    
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }
    
    var body: some View {
        Text(progressLabel)
    }
    
    private var progressLabel: String {
        let clamped = max(0, min(progress, 1))
        if clamped == 0 {
            return "0%"
        }
        if clamped < 0.01 {
            return "<1%"
        }
        if clamped < 0.1 {
            return String(format: "%.1f%%", clamped * 100)
        }
        return "\(Int(clamped * 100))%"
    }
}

private struct STTModelDownloadProgressBar: View {
    let progress: Double
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        GeometryReader { geometry in
            let clamped = max(0, min(progress, 1))
            let track = Capsule()
            
            ZStack(alignment: .leading) {
                track
                    .fill(colorScheme == .dark ? Color.white.opacity(0.08) : DS.color.surface3.opacity(0.7))
                
                if clamped <= 0 {
                    TimelineView(.animation) { context in
                        let segmentWidth = max(geometry.size.width * 0.34, 28)
                        let cycle = 1.05
                        let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle) / cycle
                        let travel = geometry.size.width + segmentWidth
                        let offset = -segmentWidth + travel * phase
                        
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        DS.color.accent.opacity(0.08),
                                        DS.color.accent.opacity(0.9),
                                        DS.color.accent.opacity(0.08),
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: segmentWidth)
                            .offset(x: offset)
                    }
                } else {
                    Capsule()
                        .fill(DS.color.accent)
                        .frame(width: max(geometry.size.height, geometry.size.width * clamped))
                }
            }
            .clipShape(track)
        }
    }
}

struct SettingsAccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(.white)
            .padding(.horizontal, SettingsTokens.Padding.buttonPrimaryHorizontal)
            .frame(height: SettingsTokens.Size.buttonHeight)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(DS.color.accent.opacity(configuration.isPressed ? 0.85 : 1))
            )
    }
}

private struct SettingsDangerButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(colorScheme == .dark ? DS.color.warningDark : DS.color.warning)
            .padding(.horizontal, SettingsTokens.Padding.buttonHorizontal)
            .frame(height: SettingsTokens.Size.buttonHeight)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill((colorScheme == .dark ? DS.color.warningDark : DS.color.warning).opacity(configuration.isPressed ? 0.18 : 0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder((colorScheme == .dark ? DS.color.warningDark : DS.color.warning).opacity(0.28), lineWidth: 1)
            )
    }
}

private struct SettingsDangerIconButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(colorScheme == .dark ? DS.color.warningDark : DS.color.warning)
            .frame(width: SettingsTokens.Size.iconButton, height: SettingsTokens.Size.iconButton)
            .background(
                Circle()
                    .fill((colorScheme == .dark ? DS.color.warningDark : DS.color.warning).opacity(configuration.isPressed ? 0.18 : 0.1))
            )
            .overlay(
                Circle()
                    .strokeBorder((colorScheme == .dark ? DS.color.warningDark : DS.color.warning).opacity(0.24), lineWidth: 1)
            )
    }
}

struct SettingsGhostButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(foreground(configuration: configuration))
            .padding(.horizontal, SettingsTokens.Padding.buttonHorizontal)
            .frame(height: SettingsTokens.Size.buttonHeight)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(background(configuration: configuration))
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(border, lineWidth: 1)
                    )
            )
    }
    
    private func foreground(configuration: Configuration) -> Color {
        if colorScheme == .dark {
            return DS.color.accentDark.opacity(configuration.isPressed ? 0.82 : 1)
        }
        return DS.color.accent.opacity(configuration.isPressed ? 0.72 : 1)
    }
    
    private func background(configuration: Configuration) -> Color {
        if colorScheme == .dark {
            return DS.color.accentDark.opacity(configuration.isPressed ? 0.16 : 0.12)
        }
        return DS.color.accent.opacity(0.08)
    }
    
    private var border: Color {
        if colorScheme == .dark {
            return DS.color.accentDark.opacity(0.3)
        }
        return DS.color.accent.opacity(0.16)
    }
}

private struct SettingsIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(DS.color.accent.opacity(configuration.isPressed ? 0.72 : 1))
            .frame(width: SettingsTokens.Size.iconButton, height: SettingsTokens.Size.iconButton)
            .background(
                Circle()
                    .fill(DS.color.accent.opacity(0.08))
            )
    }
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum SettingsRemoteProbeAudio {
    static let sample = AudioData(
        samples: Data(base64Encoded: "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")!,
        sampleRate: 16000,
        channels: 1
    )
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentRowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var maxRowWidth: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX > 0 && currentX + size.width > maxWidth {
                totalHeight += currentRowHeight + lineSpacing
                maxRowWidth = max(maxRowWidth, currentX - spacing)
                currentX = 0
                currentRowHeight = 0
            }
            
            currentX += size.width + spacing
            currentRowHeight = max(currentRowHeight, size.height)
        }
        
        if currentRowHeight > 0 {
            totalHeight += currentRowHeight
            maxRowWidth = max(maxRowWidth, currentX - spacing)
        }
        
        return CGSize(width: min(maxWidth, maxRowWidth), height: totalHeight)
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

