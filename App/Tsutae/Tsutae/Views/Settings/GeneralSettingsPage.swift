import ServiceManagement
import SwiftUI
import TsutaeCore

struct GeneralSettingsPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: SettingsTokens.Spacing.section) {
            GeneralSettingsView()
        }
    }
}

struct GeneralSettingsView: View {
    
    @ObservedObject private var hotkeyManager = GlobalHotkeyManager.shared
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage(AppPresentationController.showDockIconDefaultsKey) private var showDockIcon = false
    @State private var didSyncLaunchAtLogin = false
    @AppStorage("settings.appearanceMode") private var appearanceMode = "system"
    @AppStorage(L10n.appLanguageDefaultsKey) private var appLanguage = L10n.AppLanguage.system.rawValue
    @AppStorage("settings.defaultAction") private var defaultAction = "injectFocusedApp"
    @AppStorage(DS.recordingBar.presetDefaultsKey) private var recordingBarPreset = DS.recordingBar.defaultPreset.rawValue
    
    private let appearanceOptions = [
        SettingsDropdownOption(id: "system", title: L10n.Settings.appearanceSystem),
        SettingsDropdownOption(id: "light", title: L10n.Settings.appearanceLight),
        SettingsDropdownOption(id: "dark", title: L10n.Settings.appearanceDark)
    ]
    
    private let languageOptions = [
        SettingsDropdownOption(id: L10n.AppLanguage.system.rawValue, title: L10n.Settings.appearanceSystem),
        SettingsDropdownOption(id: L10n.AppLanguage.english.rawValue, title: L10n.Settings.languageEnglish),
        SettingsDropdownOption(id: L10n.AppLanguage.simplifiedChinese.rawValue, title: L10n.Settings.languageChinese)
    ]
    
    private let defaultActionOptions = [
        SettingsDropdownOption(id: "injectFocusedApp", title: L10n.Settings.actionInjectFocusedApp),
        SettingsDropdownOption(id: "copyToClipboard", title: L10n.Settings.actionCopyToClipboard)
    ]
    
    private var launchAtLoginSelection: Binding<String> {
        Binding(
            get: { launchAtLogin ? "on" : "off" },
            set: { updateLaunchAtLogin($0 == "on") }
        )
    }

    private var showDockIconSelection: Binding<String> {
        Binding(
            get: { showDockIcon ? "on" : "off" },
            set: { updateDockIconVisibility($0 == "on") }
        )
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsSection(title: L10n.Settings.sectionAppearance) {
                SettingsRow(label: L10n.Settings.appearanceModeLabel) {
                    SettingsDropdown(selection: $appearanceMode, options: appearanceOptions, width: SettingsTokens.Width.appearanceDropdown, menuWidth: SettingsTokens.Width.appearanceDropdownMenu)
                }
                
                SettingsDivider()
                
                SettingsRow(label: L10n.Settings.appLanguageLabel) {
                    SettingsDropdown(selection: $appLanguage, options: languageOptions, width: SettingsTokens.Width.appearanceDropdown, menuWidth: SettingsTokens.Width.appearanceDropdownMenu)
                }
                
                SettingsDivider()
                
                SettingsRow(label: L10n.Settings.recordingCapsuleLabel) {
                    SettingsChipSelector(selection: $recordingBarPreset, options: DS.recordingBar.Preset.allCases.map { ($0.rawValue, $0.title) })
                        .onChange(of: recordingBarPreset) { _, newValue in
                            FloatingRecordingBar.shared.reloadIfShowing()
                            TTSGeneralPresentationStyle.syncConfigDefault(toRecordingBarPresetRawValue: newValue)
                        }
                }
            }
            
            SettingsSection(title: L10n.Settings.sectionBehavior) {
                SettingsRow(label: L10n.Settings.recordingShortcutLabel) {
                    SettingsShortcutRecorderField(
                        shortcutID: hotkeyManager.toggleRecordingShortcutID,
                        onChange: { hotkeyManager.updateToggleRecordingShortcut(id: $0) }
                    )
                }
                
                SettingsDivider()
                
                SettingsRow(label: L10n.Settings.launchAtLoginLabel) {
                    SettingsChipSelector(
                        selection: launchAtLoginSelection,
                        options: [
                            ("off", L10n.Settings.toggleOff),
                            ("on", L10n.Settings.toggleOn)
                        ]
                    )
                }
                
                SettingsDivider()

                SettingsRow(label: L10n.Settings.showDockIconLabel) {
                    SettingsChipSelector(
                        selection: showDockIconSelection,
                        options: [
                            ("off", L10n.Settings.toggleOff),
                            ("on", L10n.Settings.toggleOn)
                        ]
                    )
                }

                SettingsDivider()
                
                SettingsRow(label: L10n.Settings.defaultActionLabel) {
                    SettingsDropdown(selection: $defaultAction, options: defaultActionOptions, width: SettingsTokens.Width.defaultActionDropdown, menuWidth: SettingsTokens.Width.defaultActionDropdown)
                }
                
                SettingsDivider()
                
                SettingsRow(label: L10n.Settings.permissionsEntryLabel) {
                    Button(L10n.Settings.permissionsEntryButton) {
                        FloatingRecordingBar.shared.openAppSettings(tab: "permissions")
                    }
                    .buttonStyle(.bordered)
                }
            }
            
            SettingsSection(title: L10n.Settings.sectionReset) {
                HStack {
                    Button(L10n.Settings.resetDefaultsButton) {
                        resetDefaults()
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                }
                .padding(.horizontal, SettingsTokens.Padding.sectionHorizontal)
                .frame(height: 52)
            }
        }
        .onAppear {
            syncLaunchAtLoginState()
            TTSGeneralPresentationStyle.syncConfigDefaultToCurrent()
        }
    }
    
    private func syncLaunchAtLoginState() {
        guard didSyncLaunchAtLogin == false else { return }
        didSyncLaunchAtLogin = true
        guard #available(macOS 13.0, *) else { return }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
    
    private func updateLaunchAtLogin(_ newValue: Bool) {
        guard launchAtLogin != newValue else { return }
        if #available(macOS 13.0, *) {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                launchAtLogin = SMAppService.mainApp.status == .enabled
            } catch {
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        } else {
            launchAtLogin = newValue
        }
    }

    private func updateDockIconVisibility(_ newValue: Bool) {
        guard showDockIcon != newValue else { return }
        showDockIcon = newValue
        AppPresentationController.shared.setDockIconVisible(newValue)
    }
    
    private func resetDefaults() {
        updateLaunchAtLogin(false)
        updateDockIconVisibility(false)
        appearanceMode = "system"
        appLanguage = L10n.AppLanguage.system.rawValue
        recordingBarPreset = DS.recordingBar.defaultPreset.rawValue
        TTSGeneralPresentationStyle.syncConfigDefault(toRecordingBarPresetRawValue: recordingBarPreset)
        defaultAction = "injectFocusedApp"
        hotkeyManager.resetToggleRecordingShortcutToDefault()
    }
}
