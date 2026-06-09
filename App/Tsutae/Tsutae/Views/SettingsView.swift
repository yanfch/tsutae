import SwiftUI

// MARK: - Settings View

extension Notification.Name {
    static let tsutaeConfigDidChange = Notification.Name("tsutae.configDidChange")
}

struct SettingsView: View {
    
    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var sidebarSelectionAnimation
    @AppStorage("settings.appearanceMode") private var appearanceMode = "system"
    @AppStorage(L10n.appLanguageDefaultsKey) private var appLanguage = L10n.AppLanguage.system.rawValue
    @AppStorage("settings.selectedTab") private var selectedTabRaw = SettingsTab.general.rawValue
    @StateObject private var sttStore = STTSettingsStore()
    @State private var selectedTabState: SettingsTab = .general
    @State private var titlebarCompensation: CGFloat = 0
    
    var body: some View {
        SettingsWindowHost(
            content: AnyView(
                settingsShell
                    .padding(.top, titlebarCompensation)
                    .tint(DS.color.brandBlue)
                    .preferredColorScheme(preferredColorScheme)
            ),
            titlebarCompensation: $titlebarCompensation,
            colorScheme: resolvedColorScheme,
            appearanceOverride: preferredColorScheme
        )
        .id(appLanguage)
        .onAppear {
            selectedTabState = SettingsTab(rawValue: selectedTabRaw) ?? .general
        }
        .onChange(of: selectedTabState) { _, newValue in
            selectedTabRaw = newValue.rawValue
        }
        .onChange(of: selectedTabRaw) { _, newValue in
            let resolved = SettingsTab(rawValue: newValue) ?? .general
            if resolved != selectedTabState {
                selectedTabState = resolved
            }
        }
    }
    
    private var settingsShell: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(settingsBackground)
            
            VStack(spacing: 0) {
                Rectangle()
                    .fill(settingsBackground)
                    .frame(height: 34)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(resolvedColorScheme == .dark ? Color.white.opacity(0.035) : Color.black.opacity(0.05))
                            .frame(height: 1)
                    }
                
                HStack(spacing: 0) {
                    SettingsSidebar(
                        selectedTab: selectedTabBinding,
                        selectionAnimation: sidebarSelectionAnimation
                    )
                    .frame(width: 232)
                    
                    Divider()
                        .overlay(resolvedColorScheme == .dark ? Color.white.opacity(0.038) : Color.black.opacity(0.05))
                    
                    VStack(spacing: 0) {
                        SettingsPageChrome(tab: selectedTab)
                        
                        ScrollView {
                            currentTabView
                                .padding(.horizontal, 28)
                                .padding(.top, 18)
                                .padding(.bottom, 24)
                        }
                        .scrollIndicators(.never)
                        .background(settingsBackground)
                    }
                    .background(settingsBackground)
                }
            }
        }
        .frame(width: 980, height: 680)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(resolvedColorScheme == .dark ? Color.black.opacity(0.58) : Color.black.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .compositingGroup()
    }
    
    private var preferredColorScheme: ColorScheme? {
        switch appearanceMode {
        case "light":
            return .light
        case "dark":
            return .dark
        default:
            return nil
        }
    }
    
    private var resolvedColorScheme: ColorScheme {
        preferredColorScheme ?? colorScheme
    }
    
    @ViewBuilder
    private var currentTabView: some View {
        switch selectedTab {
        case .general:
            GeneralSettingsPage()
        case .stt:
            STTSettingsPage(store: sttStore)
        case .tts:
            TTSSettingsPage()
        case .server:
            ServerSettingsPage()
        case .permissions:
            PermissionsSettingsPage()
        case .developer:
            DeveloperToolsPage(store: sttStore)
        default:
            SettingsPlaceholderView(tab: selectedTab)
        }
    }
    
    private var selectedTab: SettingsTab {
        selectedTabState
    }
    
    private var selectedTabBinding: Binding<SettingsTab> {
        Binding(
            get: { selectedTabState },
            set: { newValue in
                withAnimation(.snappy(duration: 0.18, extraBounce: 0)) {
                    selectedTabState = newValue
                }
            }
        )
    }
    
    private var settingsBackground: Color {
        resolvedColorScheme == .dark ? DS.color.surfaceDark : DS.color.settingsBgLight
    }
}

// MARK: - Tab Definition

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case stt
    case tts
    case server
    case permissions
    case vad
    case hotkeys
    case recipes
    case secrets
    case about
    case developer
    
    var id: String { rawValue }
    
    static let primaryTabs: [SettingsTab] = [.general, .stt, .tts, .server, .permissions]
    static var secondaryTabs: [SettingsTab] {
        #if DEBUG
        return [.vad, .hotkeys, .recipes, .secrets, .about, .developer]
        #else
        return [.vad, .hotkeys, .recipes, .secrets, .about]
        #endif
    }
    
    var title: String {
        switch self {
        case .general: return L10n.Settings.tabGeneral
        case .stt: return L10n.Settings.tabSTT
        case .tts: return L10n.Settings.tabTTS
        case .server: return L10n.Settings.tabServer
        case .permissions: return L10n.Settings.tabPermissions
        case .vad: return L10n.Settings.tabVAD
        case .hotkeys: return L10n.Settings.tabHotkeys
        case .recipes: return L10n.Settings.tabRecipes
        case .secrets: return L10n.Settings.tabSecrets
        case .about: return L10n.Settings.tabAbout
        case .developer: return L10n.Settings.tabDeveloper
        }
    }
    
    var subtitle: String {
        switch self {
        case .general:
            return L10n.Settings.subtitleGeneral
        case .stt:
            return L10n.Settings.subtitleSTT
        case .tts:
            return L10n.Settings.subtitleTTS
        case .server:
            return L10n.Settings.subtitleServer
        case .permissions:
            return L10n.Settings.subtitlePermissions
        case .vad:
            return L10n.Settings.subtitleVAD
        case .hotkeys:
            return L10n.Settings.subtitleHotkeys
        case .recipes:
            return L10n.Settings.subtitleRecipes
        case .secrets:
            return L10n.Settings.subtitleSecrets
        case .about:
            return L10n.Settings.subtitleAbout
        case .developer:
            return L10n.Settings.subtitleDeveloper
        }
    }
    
    var statusTitle: String {
        switch self {
        case .general:
            return L10n.Settings.statusReady
        case .stt:
            return L10n.Settings.statusTranscribe
        case .tts:
            return L10n.Settings.statusSpeak
        case .server:
            return L10n.Settings.statusServe
        case .permissions:
            return L10n.Settings.statusReview
        case .vad, .hotkeys, .recipes, .secrets, .about:
            return L10n.Settings.statusPrototype
        case .developer:
            return L10n.Settings.statusDebug
        }
    }
    
    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .stt: return "mic"
        case .tts: return "speaker.wave.2"
        case .server: return "server.rack"
        case .permissions: return "checkmark.shield"
        case .vad: return "waveform.path.ecg"
        case .hotkeys: return "keyboard"
        case .recipes: return "clipboard"
        case .secrets: return "key"
        case .about: return "info.circle"
        case .developer: return "hammer"
        }
    }
}
