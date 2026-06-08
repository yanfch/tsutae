import Foundation

import SwiftUI

enum L10n {
    static let appLanguageDefaultsKey = "settings.appLanguage"
    
    enum AppLanguage: String, CaseIterable {
        case system
        case english = "en"
        case simplifiedChinese = "zh-Hans"
        
        init(rawStoredValue: String) {
            self = AppLanguage(rawValue: rawStoredValue) ?? .system
        }
        
        var locale: Locale {
            switch self {
            case .system:
                return .autoupdatingCurrent
            case .english:
                return Locale(identifier: "en")
            case .simplifiedChinese:
                return Locale(identifier: "zh-Hans")
            }
        }
        
        var bundle: Bundle {
            switch self {
            case .system:
                return systemBundle
            case .english:
                return .main
            case .simplifiedChinese:
                return localizedBundle(named: "zh-Hans") ?? .main
            }
        }
        
        private var systemBundle: Bundle {
            let preferred = Locale.preferredLanguages.first ?? "en"
            if preferred.hasPrefix("zh-Hans") || preferred.hasPrefix("zh-CN") || preferred.hasPrefix("zh-SG") {
                return localizedBundle(named: "zh-Hans") ?? .main
            }
            return .main
        }
        
        private func localizedBundle(named name: String) -> Bundle? {
            guard let path = Bundle.main.path(forResource: name, ofType: "lproj") else {
                return nil
            }
            return Bundle(path: path)
        }
    }
    
    static var currentAppLanguage: AppLanguage {
        AppLanguage(rawStoredValue: UserDefaults.standard.string(forKey: appLanguageDefaultsKey) ?? AppLanguage.system.rawValue)
    }
    
    static var currentLocale: Locale {
        currentAppLanguage.locale
    }
    
    enum Common {
        static var dismiss: String { tr("common.dismiss", default: "Dismiss") }
        static var notNow: String { tr("common.not_now", default: "Not Now") }
        static var openSettings: String { tr("common.open_settings", default: "Open Settings") }
        static var openSystemSettings: String { tr("common.open_system_settings", default: "Open System Settings") }
        static var openAccessibilitySettings: String { tr("common.open_accessibility_settings", default: "Open Accessibility Settings") }
    }
    
    enum Menu {
        static var copyLatestTranscript: String { tr("menu.copy_latest_transcript", default: "Copy Latest Transcript") }
        static func error(_ value: String) -> String {
            String(format: tr("menu.error_format", default: "Error: %@"), value)
        }
        static func shortcut(_ value: String) -> String {
            String(format: tr("menu.shortcut_format", default: "Shortcut: %@"), value)
        }
        static var stopAndTranscribe: String { tr("menu.stop_and_transcribe", default: "Stop and Transcribe") }
        static var startRecording: String { tr("menu.start_recording", default: "Start Recording") }
        static var settings: String { tr("menu.settings", default: "Settings…") }
        static var quit: String { tr("menu.quit", default: "Quit tsutae") }
    }
    
    enum Notification {
        static var insertedTextTitle: String { tr("notification.inserted_text_title", default: "Text Inserted") }
    }
    
    enum RecordingCompanion {
        static var microphoneAccessRequiredTitle: String { tr("companion.microphone_access_required_title", default: "Microphone Required") }
        static var microphoneAccessRequiredMessage: String { tr("companion.microphone_access_required_message", default: "Turn on Microphone to start recording.") }
        static var noMicrophoneDetectedTitle: String { tr("companion.no_microphone_detected_title", default: "No Microphone Detected") }
        static var noMicrophoneDetectedMessage: String { tr("companion.no_microphone_detected_message", default: "No microphone input device is available right now. Check your audio input and try again.") }
        static var audioInputUnavailableTitle: String { tr("companion.audio_input_unavailable_title", default: "Audio Input Unavailable") }
        static var audioInputUnavailableMessage: String { tr("companion.audio_input_unavailable_message", default: "Tsutae couldn’t prepare the microphone input format. Try another input device and record again.") }
        static var recordingFailedTitle: String { tr("companion.recording_failed_title", default: "Recording Failed") }
        static var couldntFinishRecordingTitle: String { tr("companion.couldnt_finish_recording_title", default: "Couldn’t Finish Recording") }
        static var transcriptionUnavailableTitle: String { tr("companion.transcription_unavailable_title", default: "Transcription Unavailable") }
        static var transcriptionNetworkMessage: String { tr("companion.transcription_network_message", default: "Check your network connection and try again.") }
        static var transcriptionTimeoutMessage: String { tr("companion.transcription_timeout_message", default: "The transcription service timed out. Try again or check the service status.") }
        static var transcriptionUnreachableMessage: String { tr("companion.transcription_unreachable_message", default: "Cannot reach the transcription service. Check network, endpoint, or model settings.") }
        static var authenticationFailedTitle: String { tr("companion.authentication_failed_title", default: "Authentication Failed") }
        static var authenticationFailedMessage: String { tr("companion.authentication_failed_message", default: "Check your API key or service permissions before trying again.") }
        static var speechRecognitionAccessRequiredTitle: String { tr("companion.speech_recognition_access_required_title", default: "Speech Recognition Required") }
        static var speechRecognitionAccessRequiredMessage: String { tr("companion.speech_recognition_access_required_message", default: "Turn on Speech Recognition to use Apple fallback.") }
        static var sttConfigurationErrorTitle: String { tr("companion.stt_configuration_error_title", default: "STT Configuration Error") }
        static var sttConfigurationErrorMessage: String { tr("companion.stt_configuration_error_message", default: "Check the model, endpoint, or request settings for transcription.") }
        static var transcriptionFailedTitle: String { tr("companion.transcription_failed_title", default: "Transcription Failed") }
        static var transcriptionFailedMessage: String { tr("companion.transcription_failed_message", default: "The transcription service returned an unexpected error. Check your service settings and try again.") }
        static var accessibilityAccessRequiredTitle: String { tr("companion.accessibility_access_required_title", default: "Accessibility Required") }
        static var accessibilityAccessRequiredMessage: String { tr("companion.accessibility_access_required_message", default: "Turn on Accessibility so Tsutae can insert text into the focused app.") }
        static var copiedToClipboardTitle: String { tr("companion.copied_to_clipboard_title", default: "Copied to Clipboard") }
        static var copiedToClipboardMessage: String { tr("companion.copied_to_clipboard_message", default: "Couldn’t insert into the focused app. The transcript was copied instead.") }
        static var preparingLocalModelTitle: String { tr("companion.preparing_local_model_title", default: "Preparing Model") }
        static var preparingLocalModelMessage: String { tr("companion.preparing_local_model_message", default: "First load may take a moment.") }
    }
    
    enum Settings {
        static var windowTitle: String { tr("settings.window_title", default: "tsutae Settings") }
        static var sectionAppearance: String { tr("settings.section_appearance", default: "Appearance") }
        static var sectionBehavior: String { tr("settings.section_behavior", default: "Behavior") }
        static var sectionReset: String { tr("settings.section_reset", default: "Reset") }
        static var themeColorLabel: String { tr("settings.theme_color_label", default: "Theme Color") }
        static var themePreviewLabel: String { tr("settings.theme_preview_label", default: "Theme Preview") }
        static var appearanceModeLabel: String { tr("settings.appearance_mode_label", default: "Appearance") }
        static var appLanguageLabel: String { tr("settings.app_language_label", default: "App Language") }
        static var recordingCapsuleLabel: String { tr("settings.recording_capsule_label", default: "Recording Capsule") }
        static var launchAtLoginLabel: String { tr("settings.launch_at_login_label", default: "Launch at Login") }
        static var defaultActionLabel: String { tr("settings.default_action_label", default: "Default Action") }
        static var transcriptionLanguageLabel: String { tr("settings.transcription_language_label", default: "Transcription Language") }
        static var accessibilityPermissionLabel: String { tr("settings.accessibility_permission_label", default: "Accessibility Permission") }
        static var permissionsEntryLabel: String { tr("settings.permissions_entry_label", default: "Permissions") }
        static var permissionsEntryButton: String { tr("settings.permissions_entry_button", default: "Review") }
        static var openSystemSettingsButton: String { tr("settings.open_system_settings_button", default: "Open System Settings") }
        static var resetDefaultsButton: String { tr("settings.reset_defaults_button", default: "Reset to Defaults") }
        static var themeDefaultBlue: String { tr("settings.theme_default_blue", default: "Default Blue") }
        static var themeFollowSystem: String { tr("settings.theme_follow_system", default: "Follow System") }
        static var themeCustom: String { tr("settings.theme_custom", default: "Custom") }
        static var appearanceSystem: String { tr("settings.appearance_system", default: "System") }
        static var appearanceLight: String { tr("settings.appearance_light", default: "Light") }
        static var appearanceDark: String { tr("settings.appearance_dark", default: "Dark") }
        static var actionInjectFocusedApp: String { tr("settings.action_inject_focused_app", default: "Insert into Focused App") }
        static var actionCopyToClipboard: String { tr("settings.action_copy_to_clipboard", default: "Copy to Clipboard") }
        static var languageAuto: String { tr("settings.language_auto", default: "Auto") }
        static var languageChinese: String { tr("settings.language_chinese", default: "Chinese") }
        static var languageEnglish: String { tr("settings.language_english", default: "English") }
        static var tabGeneral: String { tr("settings.tab_general", default: "General") }
        static var tabSTT: String { tr("settings.tab_stt", default: "Speech to Text") }
        static var tabTTS: String { tr("settings.tab_tts", default: "Text to Speech") }
        static var tabVAD: String { tr("settings.tab_vad", default: "Voice Activity Detection") }
        static var tabHotkeys: String { tr("settings.tab_hotkeys", default: "Hotkeys") }
        static var tabRecipes: String { tr("settings.tab_recipes", default: "Recipes") }
        static var tabSecrets: String { tr("settings.tab_secrets", default: "Secrets") }
        static var tabServer: String { tr("settings.tab_server", default: "Server") }
        static var tabAbout: String { tr("settings.tab_about", default: "About") }
        static func placeholderTitle(_ tabTitle: String) -> String {
            String(format: tr("settings.placeholder_title_format", default: "%@ Settings"), tabTitle)
        }
        static var placeholderDescription: String { tr("settings.placeholder_description", default: "Real configuration will be added next using the same card structure.") }
    }
    
    enum RecordingBar {
        static var presetStandard: String { tr("recording_bar.preset_standard", default: "Standard") }
        static var presetMinimal: String { tr("recording_bar.preset_minimal", default: "Minimal") }
    }
    
    private static func tr(_ key: String, `default` defaultValue: String) -> String {
        NSLocalizedString(key, tableName: nil, bundle: currentAppLanguage.bundle, value: defaultValue, comment: "")
    }
}
