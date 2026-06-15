import AppKit
import SwiftUI
import TsutaeCore

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
                        isRuntimeExpanded.toggle()
                    } label: {
                        Label(
                            isRuntimeExpanded ? L10n.Settings.serverRuntimeCollapseButton : L10n.Settings.serverRuntimeConfigureButton,
                            systemImage: isRuntimeExpanded ? "chevron.up" : "slider.horizontal.3"
                        )
                    }
                    .buttonStyle(.bordered)
                }

                if isRuntimeExpanded {
                    SettingsFeatureToggleRow(
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
                        SettingsFormRow(label: L10n.Settings.labelBaseURL) {
                            HStack(spacing: 10) {
                                Text(baseURLString)
                                    .font(DS.font.mono(size: 12, weight: .regular))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)

                                Button {
                                    copyEndpoint(id: "base", title: L10n.Settings.labelBaseURL, path: "")
                                } label: {
                                    Label(L10n.Settings.serverCopyButton, systemImage: "doc.on.doc")
                                        .labelStyle(.iconOnly)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        SettingsDivider()
                        SettingsFormRow(label: L10n.Settings.serverBindLabel) {
                            SettingsInlineTextField(text: $bindDraft, placeholder: "127.0.0.1", width: 190)
                        }
                        SettingsDivider()
                        SettingsFormRow(label: L10n.Settings.serverPortLabel) {
                            SettingsInlineTextField(text: $portDraft, placeholder: "1338", width: 110)
                        }
                    }

                    SettingsFeatureToggleRow(
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
                } else if config.server.clients.count > 4 {
                    ScrollView {
                        serverClientRows
                    }
                    .frame(maxHeight: clientListMaxHeight)
                } else {
                    serverClientRows
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

    private var serverClientRows: some View {
        LazyVStack(spacing: 10) {
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
                        if client.enabled {
                            Button {
                                setSelectedClientEnabled(false)
                            } label: {
                                Label(L10n.Settings.serverClientDisableButton, systemImage: "pause.circle")
                            }
                            .buttonStyle(.bordered)
                        } else {
                            Button {
                                setSelectedClientEnabled(true)
                            } label: {
                                Label(L10n.Settings.serverClientEnableButton, systemImage: "play.circle")
                            }
                            .buttonStyle(SettingsAccentButtonStyle())
                        }

                        Button {
                            regenerateSelectedClientToken()
                        } label: {
                            Label(L10n.Settings.serverClientRegenerateTokenButton, systemImage: "arrow.clockwise")
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

            serverClientUsageCard(client)
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
                HStack(spacing: 10) {
                    Text(L10n.Settings.serverClientCommonScopesTitle)
                        .font(.system(size: 13, weight: .medium))
                    ServerStatusCapsule(
                        title: L10n.Settings.serverClientScopeCount(enabledScopeCount(in: primaryClientScopes, client: client)),
                        tone: enabledScopeCount(in: primaryClientScopes, client: client) > 0 ? .active : .neutral
                    )
                    Spacer(minLength: 0)
                }

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
                        isAdvancedScopesExpanded.toggle()
                    } label: {
                        Label(
                            isAdvancedScopesExpanded ? L10n.Settings.serverClientHideAdvancedScopes : L10n.Settings.serverClientShowAdvancedScopes,
                            systemImage: isAdvancedScopesExpanded ? "chevron.up" : "chevron.down"
                        )
                    }
                    .buttonStyle(.bordered)
                }

                if isAdvancedScopesExpanded {
                    Text(L10n.Settings.serverClientAdvancedScopesNote)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    clientScopeGrid(advancedClientScopes, client: client)
                }
            }
        }
    }

    private func serverClientUsageCard(_ client: Config.ServerClientConfig) -> some View {
        SettingsDashboardCard(title: L10n.Settings.serverClientUsageTitle, subtitle: L10n.Settings.serverClientUsageSubtitle) {
            VStack(alignment: .leading, spacing: SettingsTokens.Spacing.content) {
                HStack(spacing: 8) {
                    ServerStatusCapsule(title: baseURLString, tone: .soft)
                    ServerStatusCapsule(title: client.enabled ? L10n.Settings.serverClientStatusEnabled : L10n.Settings.serverClientStatusDisabled, tone: client.enabled ? .success : .neutral)
                    Spacer(minLength: 0)
                }

                Text(clientExampleCommand(for: client))
                    .font(DS.font.mono(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.primary.opacity(0.035))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color.secondary.opacity(0.14), lineWidth: 1)
                            )
                    )

                HStack(spacing: 10) {
                    Button {
                        copyClientExample(for: client)
                    } label: {
                        Label(L10n.Settings.serverClientCopyExampleButton, systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)

                    if visibleToken(for: client) == nil {
                        Text(L10n.Settings.serverClientExampleTokenUnavailable)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
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
                SettingsFeatureToggleRow(
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
                                .toggleStyle(SettingsFeatureSwitchToggleStyle())
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

    private var clientListMaxHeight: CGFloat {
        360
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

    private func copyClientExample(for client: Config.ServerClientConfig) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(clientExampleCommand(for: client), forType: .string)
        clientStatusText = L10n.Settings.serverClientExampleCopiedStatus
    }

    private func visibleToken(for client: Config.ServerClientConfig) -> String? {
        guard generatedClientTokenClientID == client.id else { return nil }
        return generatedClientToken
    }

    private func clientExampleCommand(for client: Config.ServerClientConfig) -> String {
        let token = visibleToken(for: client) ?? "<token>"
        return """
        curl -s \(baseURLString)/v1/notify \\
          -H 'Authorization: Bearer \(token)' \\
          -H 'Content-Type: application/json' \\
          -d '{"message":"Hello from \(client.name)","notify":true,"speak":false}'
        """
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
            return L10n.Settings.serverClientScopeModelsTitle
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
            return L10n.Settings.serverClientScopeListenTitle
        case .recipes:
            return L10n.Settings.serverClientScopeRecipesTitle
        case .secrets:
            return L10n.Settings.serverClientScopeSecretsTitle
        case .configRead:
            return L10n.Settings.serverClientScopeConfigReadTitle
        }
    }

    private func clientScopeDescription(_ scope: Config.ServerClientScope) -> String {
        switch scope {
        case .state:
            return L10n.Settings.serverClientScopeStateDescription
        case .models:
            return L10n.Settings.serverClientScopeModelsDescription
        case .transcribe:
            return L10n.Settings.serverClientScopeTranscribeDescription
        case .audioSpeech:
            return L10n.Settings.serverClientScopeAudioSpeechDescription
        case .speak:
            return L10n.Settings.serverClientScopeSpeakDescription
        case .notify:
            return L10n.Settings.serverClientScopeNotifyDescription
        case .stop:
            return L10n.Settings.serverClientScopeStopDescription
        case .listen:
            return L10n.Settings.serverClientScopeListenDescription
        case .recipes:
            return L10n.Settings.serverClientScopeRecipesDescription
        case .secrets:
            return L10n.Settings.serverClientScopeSecretsDescription
        case .configRead:
            return L10n.Settings.serverClientScopeConfigReadDescription
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
            .buttonStyle(SettingsCircularIconButtonStyle())
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
