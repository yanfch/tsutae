import SwiftUI
import TsutaeCore

// MARK: - Settings View

struct SettingsView: View {
    
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("settings.appearanceMode") private var appearanceMode = "system"
    @AppStorage(L10n.appLanguageDefaultsKey) private var appLanguage = L10n.AppLanguage.system.rawValue
    @AppStorage("settings.selectedTab") private var selectedTabRaw = SettingsTab.general.rawValue
    
    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selectedTab: selectedTabBinding)
            
            Divider()
                .overlay(colorScheme == .dark ? Color.white.opacity(0.1) : Color.clear)
            
            VStack(spacing: 0) {
                // 标题栏
                Text(L10n.Settings.windowTitle)
                    .font(.system(.title3, design: .default).weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 72)
                    .background(settingsBackground)
                    .overlay(alignment: .bottom) {
                        Divider()
                            .overlay(colorScheme == .dark ? Color.white.opacity(0.1) : Color.clear)
                    }
                
                // 内容区
                ScrollView {
                    currentTabView
                        .padding(.horizontal, 36)
                        .padding(.vertical, 28)
                }
                .scrollIndicators(.never)
                .background(settingsBackground)
            }
            .background(settingsBackground)
        }
        .id(appLanguage)
        .frame(width: 920, height: 620)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .tint(DS.color.brandBlue)
        .preferredColorScheme(preferredColorScheme)
        .background(settingsBackground)
        .background(SettingsWindowBridge())
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
    
    @ViewBuilder
    private var currentTabView: some View {
        switch selectedTab {
        case .general:
            GeneralSettingsView()
        default:
            SettingsPlaceholderView(tab: selectedTab)
        }
    }
    
    private var selectedTab: SettingsTab {
        SettingsTab(rawValue: selectedTabRaw) ?? .general
    }
    
    private var selectedTabBinding: Binding<SettingsTab> {
        Binding(
            get: { selectedTab },
            set: { selectedTabRaw = $0.rawValue }
        )
    }
    
    private var settingsBackground: Color {
        colorScheme == .dark ? DS.color.settingsBgDark : DS.color.settingsBgLight
    }
}

// MARK: - Tab Definition

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case stt
    case tts
    case vad
    case hotkeys
    case recipes
    case secrets
    case server
    case about
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .general: return L10n.Settings.tabGeneral
        case .stt: return L10n.Settings.tabSTT
        case .tts: return L10n.Settings.tabTTS
        case .vad: return L10n.Settings.tabVAD
        case .hotkeys: return L10n.Settings.tabHotkeys
        case .recipes: return L10n.Settings.tabRecipes
        case .secrets: return L10n.Settings.tabSecrets
        case .server: return L10n.Settings.tabServer
        case .about: return L10n.Settings.tabAbout
        }
    }
    
    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .stt: return "mic"
        case .tts: return "speaker.wave.2"
        case .vad: return "waveform.path.ecg"
        case .hotkeys: return "keyboard"
        case .recipes: return "clipboard"
        case .secrets: return "key"
        case .server: return "desktopcomputer"
        case .about: return "info.circle"
        }
    }
}

// MARK: - Sidebar

private struct SettingsSidebar: View {
    
    @Binding var selectedTab: SettingsTab
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 窗口控制按钮区域留白
            Spacer()
                .frame(height: 78)
            
            // 导航项
            VStack(spacing: 8) {
                ForEach(SettingsTab.allCases) { tab in
                    SidebarItem(tab: tab, isSelected: selectedTab == tab) {
                        selectedTab = tab
                    }
                }
            }
            .padding(.horizontal, 16)
            
            Spacer()
        }
        .frame(width: 236)
        .background(sidebarBackground)
    }
    
    private var sidebarBackground: some View {
        Group {
            if colorScheme == .dark {
                Color.black.opacity(0.3)
            } else {
                Color.white.opacity(0.5)
            }
        }
        .overlay(.ultraThinMaterial)
    }
}

private struct SidebarItem: View {
    
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 18) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 22, weight: .medium))
                    .symbolRenderingMode(.monochrome)
                    .frame(width: 28)
                
                Text(tab.title)
                    .font(.system(size: 16, weight: .medium))
                
                Spacer()
            }
            .foregroundStyle(itemForegroundColor)
            .padding(.horizontal, 18)
            .frame(height: 46)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(DS.color.brandBlue)
                }
            }
        }
        .buttonStyle(.plain)
    }
    
    private var itemForegroundColor: Color {
        if isSelected {
            return .white
        }
        return colorScheme == .dark ? .white.opacity(0.85) : .primary.opacity(0.82)
    }
}

// MARK: - General Settings

private struct GeneralSettingsView: View {
    
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("settings.themeMode") private var themeMode = "defaultBlue"
    @AppStorage("settings.appearanceMode") private var appearanceMode = "system"
    @AppStorage(L10n.appLanguageDefaultsKey) private var appLanguage = L10n.AppLanguage.system.rawValue
    @AppStorage("settings.defaultAction") private var defaultAction = "injectFocusedApp"
    @AppStorage("settings.transcriptionLanguage") private var transcriptionLanguage = "auto"
    @AppStorage(DS.recordingBar.presetDefaultsKey) private var recordingBarPreset = DS.recordingBar.defaultPreset.rawValue
    
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            // 外观分组
            SettingsSection(title: L10n.Settings.sectionAppearance) {
                // 主题色
                SettingsRow(label: L10n.Settings.themeColorLabel) {
                    Picker("", selection: $themeMode) {
                        Text(L10n.Settings.themeDefaultBlue).tag("defaultBlue")
                        Text(L10n.Settings.themeFollowSystem).tag("system")
                        Text(L10n.Settings.themeCustom).tag("custom")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 330)
                }
                
                SettingsDivider()
                
                // 主题色预览
                SettingsRow(label: L10n.Settings.themePreviewLabel) {
                    ThemeColorPicker(selectedTheme: $themeMode)
                }
                
                SettingsDivider()
                
                // 外观
                SettingsRow(label: L10n.Settings.appearanceModeLabel) {
                    Picker("", selection: $appearanceMode) {
                        Text(L10n.Settings.appearanceSystem).tag("system")
                        Text(L10n.Settings.appearanceLight).tag("light")
                        Text(L10n.Settings.appearanceDark).tag("dark")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 150)
                }
                
                SettingsDivider()
                
                // 界面语言
                SettingsRow(label: L10n.Settings.appLanguageLabel) {
                    Picker("", selection: $appLanguage) {
                        Text(L10n.Settings.appearanceSystem).tag(L10n.AppLanguage.system.rawValue)
                        Text(L10n.Settings.languageEnglish).tag(L10n.AppLanguage.english.rawValue)
                        Text(L10n.Settings.languageChinese).tag(L10n.AppLanguage.simplifiedChinese.rawValue)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 150)
                }
                
                SettingsDivider()
                
                // 录音胶囊样式
                SettingsRow(label: L10n.Settings.recordingCapsuleLabel) {
                    Picker("", selection: $recordingBarPreset) {
                        ForEach(DS.recordingBar.Preset.allCases, id: \.rawValue) { preset in
                            Text(preset.title).tag(preset.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                    .onChange(of: recordingBarPreset) { _, _ in
                        // 重新加载悬浮条（如果正在显示）
                        FloatingRecordingBar.shared.reloadIfShowing()
                    }
                }
            }
            
            // 行为分组
            SettingsSection(title: L10n.Settings.sectionBehavior) {
                // 开机自动启动
                SettingsRow(label: L10n.Settings.launchAtLoginLabel) {
                    Toggle("", isOn: $launchAtLogin)
                        .labelsHidden()
                }
                
                SettingsDivider()
                
                // 默认动作
                SettingsRow(label: L10n.Settings.defaultActionLabel) {
                    Picker("", selection: $defaultAction) {
                        Text(L10n.Settings.actionInjectFocusedApp).tag("injectFocusedApp")
                        Text(L10n.Settings.actionCopyToClipboard).tag("copyToClipboard")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 220)
                }
                
                SettingsDivider()
                
                // 转写语言
                SettingsRow(label: L10n.Settings.transcriptionLanguageLabel) {
                    Picker("", selection: $transcriptionLanguage) {
                        Text(L10n.Settings.languageAuto).tag("auto")
                        Text(L10n.Settings.languageChinese).tag("zh")
                        Text(L10n.Settings.languageEnglish).tag("en")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }
                
                SettingsDivider()
                
                // 辅助功能权限
                SettingsRow(label: L10n.Settings.accessibilityPermissionLabel) {
                    Button(L10n.Settings.openSystemSettingsButton) {
                        FloatingRecordingBar.shared.openSystemSettingsPrivacyPane("Privacy_Accessibility")
                    }
                    .buttonStyle(.bordered)
                }
            }
            
            // 重置分组
            SettingsSection(title: L10n.Settings.sectionReset) {
                HStack {
                    Button(L10n.Settings.resetDefaultsButton) {
                        resetDefaults()
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                }
                .padding(.horizontal, 18)
                .frame(height: 52)
            }
        }
    }
    
    private func resetDefaults() {
        launchAtLogin = false
        themeMode = "defaultBlue"
        appearanceMode = "system"
        appLanguage = L10n.AppLanguage.system.rawValue
        defaultAction = "injectFocusedApp"
        transcriptionLanguage = "auto"
    }
}

// MARK: - Theme Color Picker

private struct ThemeColorPicker: View {
    
    @Binding var selectedTheme: String
    
    var body: some View {
        HStack(spacing: 18) {
            ForEach(ThemeSwatch.allCases) { swatch in
                ThemeSwatchButton(
                    swatch: swatch,
                    isSelected: swatch.id == selectedTheme
                ) {
                    selectedTheme = swatch.id
                }
            }
        }
    }
}

private struct ThemeSwatchButton: View {
    
    let swatch: ThemeSwatch
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Circle()
                .fill(swatch.color)
                .frame(width: 30, height: 30)
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .overlay {
                    Circle()
                        .strokeBorder(
                            isSelected ? swatch.color.opacity(0.4) : Color.clear,
                            lineWidth: 8
                        )
                }
        }
        .buttonStyle(.plain)
    }
}

private enum ThemeSwatch: CaseIterable, Identifiable {
    case blue
    case orange
    case pink
    case purple
    case green
    case gray
    
    var id: String {
        switch self {
        case .blue: return "defaultBlue"
        case .orange: return "orange"
        case .pink: return "pink"
        case .purple: return "purple"
        case .green: return "green"
        case .gray: return "gray"
        }
    }
    
    var color: Color {
        switch self {
        case .blue: return DS.color.brandBlue
        case .orange: return .orange
        case .pink: return .pink
        case .purple: return .purple
        case .green: return DS.color.accent  // 松针绿
        case .gray: return .gray
        }
    }
}

// MARK: - Placeholder View

private struct SettingsPlaceholderView: View {
    
    let tab: SettingsTab
    
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            SettingsSection(title: tab.title) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.Settings.placeholderTitle(tab.title))
                        .font(.headline)
                    Text(L10n.Settings.placeholderDescription)
                        .foregroundStyle(.secondary)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Reusable Components

private struct SettingsSection<Content: View>: View {
    
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 8)
            
            VStack(spacing: 0) {
                content
            }
            .background(SettingsCardBackground())
        }
    }
}

private struct SettingsRow<Content: View>: View {
    
    let label: String
    @ViewBuilder let content: Content
    
    var body: some View {
        HStack(spacing: 16) {
            Text(label)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.primary)
            
            Spacer()
            
            content
        }
        .padding(.horizontal, 18)
        .frame(height: 52)
    }
}

private struct SettingsDivider: View {
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Divider()
            .padding(.leading, 18)
            .overlay(colorScheme == .dark ? Color.white.opacity(0.08) : Color.clear)
    }
}

private struct SettingsCardBackground: View {
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        RoundedRectangle(cornerRadius: DS.radius.card, style: .continuous)
            .fill(cardBackground)
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.0 : 0.05),
                radius: 10,
                x: 0,
                y: 2
            )
            .overlay {
                RoundedRectangle(cornerRadius: DS.radius.card, style: .continuous)
                    .strokeBorder(cardBorderColor, lineWidth: 1)
            }
    }
    
    private var cardBackground: Color {
        colorScheme == .dark ? DS.color.cardBgDark : .white
    }
    
    private var cardBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color(white: 0, opacity: 0.1)
    }
}

// MARK: - Window Bridge

private struct SettingsWindowBridge: NSViewRepresentable {
    
    @Environment(\.colorScheme) private var colorScheme
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        
        DispatchQueue.main.async {
            configureWindow(for: view, colorScheme: colorScheme)
        }
        
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configureWindow(for: nsView, colorScheme: colorScheme)
        }
    }
    
    private func configureWindow(for view: NSView, colorScheme: ColorScheme) {
        guard let window = view.window else { return }
        
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        
        // 根据 colorScheme 设置窗口背景色
        switch colorScheme {
        case .dark:
            window.backgroundColor = NSColor(red: 0x1C/255, green: 0x1C/255, blue: 0x1E/255, alpha: 1)
        case .light:
            window.backgroundColor = NSColor(red: 0xF2/255, green: 0xF2/255, blue: 0xF4/255, alpha: 1)
        @unknown default:
            window.backgroundColor = NSColor(red: 0xF2/255, green: 0xF2/255, blue: 0xF4/255, alpha: 1)
        }
        
        window.isOpaque = true
        window.isMovableByWindowBackground = true
        
        NSApp.activate(ignoringOtherApps: true)
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.level = .floating
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if window.isVisible {
                window.level = .normal
            }
        }
    }
}
