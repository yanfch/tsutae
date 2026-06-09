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
        static var select: String { tr("common.select", default: "Select") }
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
        static var quit: String { tr("menu.quit", default: "Quit Tsutae") }
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
        static var windowTitle: String { tr("settings.window_title", default: "Tsutae Settings") }
        static var sectionAppearance: String { tr("settings.section_appearance", default: "Appearance") }
        static var sectionBehavior: String { tr("settings.section_behavior", default: "Behavior") }
        static var sectionReset: String { tr("settings.section_reset", default: "Reset") }
        static var themeColorLabel: String { tr("settings.theme_color_label", default: "Theme Color") }
        static var themePreviewLabel: String { tr("settings.theme_preview_label", default: "Theme Preview") }
        static var appearanceModeLabel: String { tr("settings.appearance_mode_label", default: "Appearance") }
        static var appLanguageLabel: String { tr("settings.app_language_label", default: "App Language") }
        static var recordingCapsuleLabel: String { tr("settings.recording_capsule_label", default: "Recording Capsule") }
        static var launchAtLoginLabel: String { tr("settings.launch_at_login_label", default: "Launch at Login") }
        static var recordingShortcutLabel: String { tr("settings.recording_shortcut_label", default: "Recording Shortcut") }
        static var recordingShortcutPrompt: String { tr("settings.recording_shortcut_prompt", default: "Press") }
        static var recordingShortcutRecordHint: String { tr("settings.recording_shortcut_record_hint", default: "Set") }
        static var recordingShortcutCancelHint: String { tr("settings.recording_shortcut_cancel_hint", default: "Esc") }
        static var recordingShortcutModifierHint: String { tr("settings.recording_shortcut_modifier_hint", default: "Use at least one modifier.") }
        static var toggleOff: String { tr("settings.toggle_off", default: "Off") }
        static var toggleOn: String { tr("settings.toggle_on", default: "On") }
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
        static var tabPermissions: String { tr("settings.tab_permissions", default: "Permissions") }
        static var tabDeveloper: String { tr("settings.tab_developer", default: "Developer") }
        static var sidebarAdvanced: String { tr("settings.sidebar_advanced", default: "Advanced") }
        static var subtitleGeneral: String { tr("settings.subtitle_general", default: "Tune the everyday behavior and appearance of Tsutae.") }
        static var subtitleSTT: String { tr("settings.subtitle_stt", default: "Configure transcription engines and routing.") }
        static var subtitleTTS: String { tr("settings.subtitle_tts", default: "Prepare voices, playback, and synthesis behavior.") }
        static var subtitleServer: String { tr("settings.subtitle_server", default: "Expose local STT, TTS, hooks, and automation endpoints.") }
        static var subtitlePermissions: String { tr("settings.subtitle_permissions", default: "Review the system permissions Tsutae needs to work smoothly.") }
        static var subtitleVAD: String { tr("settings.subtitle_vad", default: "Adjust how Tsutae detects speech boundaries and silence.") }
        static var subtitleHotkeys: String { tr("settings.subtitle_hotkeys", default: "Manage the shortcuts that trigger recording and actions.") }
        static var subtitleRecipes: String { tr("settings.subtitle_recipes", default: "Organize reusable prompt and action workflows.") }
        static var subtitleSecrets: String { tr("settings.subtitle_secrets", default: "Store keys and tokens used by engines and services.") }
        static var subtitleAbout: String { tr("settings.subtitle_about", default: "Version details, diagnostics, and product information.") }
        static var subtitleDeveloper: String { tr("settings.subtitle_developer", default: "Debug-only tools for warmup, runtime state, and test flows.") }
        static var statusReady: String { tr("settings.status_ready", default: "Ready") }
        static var statusTranscribe: String { tr("settings.status_transcribe", default: "Transcribe") }
        static var statusSpeak: String { tr("settings.status_speak", default: "Speak") }
        static var statusServe: String { tr("settings.status_serve", default: "Serve") }
        static var statusReview: String { tr("settings.status_review", default: "Review") }
        static var statusPrototype: String { tr("settings.status_prototype", default: "Prototype") }
        static var statusDebug: String { tr("settings.status_debug", default: "Debug") }
        static var chromePlayback: String { tr("settings.chrome_playback", default: "Playback") }
        static var chromeCloudOptional: String { tr("settings.chrome_cloud_optional", default: "Cloud Optional") }
        static var chromeSTTTTS: String { tr("settings.chrome_stt_tts", default: "STT · TTS") }
        static var chromeHooksPlanned: String { tr("settings.chrome_hooks_planned", default: "Hooks Planned") }
        static var generalWorkflowTitle: String { tr("settings.general_workflow_title", default: "Workflow") }
        static var generalWorkflowSubtitle: String { tr("settings.general_workflow_subtitle", default: "A quick overview of the current voice pipeline.") }
        static var workflowCapture: String { tr("settings.workflow_capture", default: "Capture") }
        static var workflowTranscribe: String { tr("settings.workflow_transcribe", default: "Transcribe") }
        static var workflowInsert: String { tr("settings.workflow_insert", default: "Insert") }
        static var workflowSpeak: String { tr("settings.workflow_speak", default: "Speak") }
        static var workflowServe: String { tr("settings.workflow_serve", default: "Serve") }
        static var labelProvider: String { tr("settings.label_provider", default: "Provider") }
        static var labelVoice: String { tr("settings.label_voice", default: "Voice") }
        static var labelSpeed: String { tr("settings.label_speed", default: "Speed") }
        static var labelOutput: String { tr("settings.label_output", default: "Output") }
        static var labelSTT: String { tr("settings.label_stt", default: "STT") }
        static var labelTTS: String { tr("settings.label_tts", default: "TTS") }
        static var labelAutoPlay: String { tr("settings.label_auto_play", default: "Auto Play") }
        static var labelInterrupt: String { tr("settings.label_interrupt", default: "Interrupt") }
        static var labelQueue: String { tr("settings.label_queue", default: "Queue") }
        static var labelServerExposure: String { tr("settings.label_server_exposure", default: "Server Exposure") }
        static var labelCallbacks: String { tr("settings.label_callbacks", default: "Callbacks") }
        static var labelStreaming: String { tr("settings.label_streaming", default: "Streaming") }
        static var labelStatus: String { tr("settings.label_status", default: "Status") }
        static var labelSample: String { tr("settings.label_sample", default: "Sample") }
        static var labelHooks: String { tr("settings.label_hooks", default: "Hooks") }
        static var labelBaseURL: String { tr("settings.label_base_url", default: "Base URL") }
        static var labelAuthToken: String { tr("settings.label_auth_token", default: "Auth Token") }
        static var labelCORS: String { tr("settings.label_cors", default: "CORS") }
        static var labelCopyEndpoint: String { tr("settings.label_copy_endpoint", default: "Copy Endpoint") }
        static var labelRecentRequests: String { tr("settings.label_recent_requests", default: "Recent Requests") }
        static var labelLastError: String { tr("settings.label_last_error", default: "Last Error") }
        static var labelOnTranscribed: String { tr("settings.label_on_transcribed", default: "onTranscribed") }
        static var labelOnSpoken: String { tr("settings.label_on_spoken", default: "onSpoken") }
        static var labelOnError: String { tr("settings.label_on_error", default: "onError") }
        static var valuePrototype: String { tr("settings.value_prototype", default: "Prototype") }
        static var valueDefault: String { tr("settings.value_default", default: "Default") }
        static var valueSystem: String { tr("settings.value_system", default: "System") }
        static var valueAllowed: String { tr("settings.value_allowed", default: "Allowed") }
        static var valueSingleResponse: String { tr("settings.value_single_response", default: "Single Response") }
        static var valuePlanned: String { tr("settings.value_planned", default: "Planned") }
        static var valueComingSoon: String { tr("settings.value_coming_soon", default: "Coming Soon") }
        static var valueCompatible: String { tr("settings.value_compatible", default: "Compatible") }
        static var valueSupported: String { tr("settings.value_supported", default: "Supported") }
        static var valueFuture: String { tr("settings.value_future", default: "Future") }
        static var valueStopped: String { tr("settings.value_stopped", default: "Stopped") }
        static var valueLocalhost: String { tr("settings.value_localhost", default: "Localhost") }
        static var valueManaged: String { tr("settings.value_managed", default: "Managed") }
        static var valueConfigurable: String { tr("settings.value_configurable", default: "Configurable") }
        static var valueShortcut: String { tr("settings.value_shortcut", default: "Shortcut") }
        static var ttsVoiceEngineTitle: String { tr("settings.tts_voice_engine_title", default: "Voice Engine") }
        static var ttsVoiceEngineSubtitle: String { tr("settings.tts_voice_engine_subtitle", default: "Prepare synthesis providers and voice routing.") }
        static var ttsPlaybackTitle: String { tr("settings.tts_playback_title", default: "Playback") }
        static var ttsPlaybackSubtitle: String { tr("settings.tts_playback_subtitle", default: "Control how spoken results should behave.") }
        static var ttsPresentationStyleLabel: String { tr("settings.tts_presentation_style_label", default: "Presentation") }
        static var ttsStyleStandard: String { tr("settings.tts_style_standard", default: "Standard") }
        static var ttsStyleMinimal: String { tr("settings.tts_style_minimal", default: "Minimal") }
        static var ttsInterruptCurrentLabel: String { tr("settings.tts_interrupt_current_label", default: "Interrupt") }
        static var ttsPreviewTitle: String { tr("settings.tts_preview_title", default: "Preview") }
        static var ttsPreviewSubtitle: String { tr("settings.tts_preview_subtitle", default: "This space will host quick synthesis testing.") }
        static var ttsPreviewTextLabel: String { tr("settings.tts_preview_text_label", default: "Preview Text") }
        static var ttsPreviewPlaceholder: String { tr("settings.tts_preview_placeholder", default: "Type a short phrase") }
        static var ttsPreviewPlayButton: String { tr("settings.tts_preview_play_button", default: "Play Preview") }
        static var ttsPreviewStopButton: String { tr("settings.tts_preview_stop_button", default: "Stop") }
        static var ttsStatusIdle: String { tr("settings.tts_status_idle", default: "Idle") }
        static var ttsStatusSpeaking: String { tr("settings.tts_status_speaking", default: "Speaking") }
        static var ttsIntegrationTitle: String { tr("settings.tts_integration_title", default: "Integration") }
        static var ttsIntegrationSubtitle: String { tr("settings.tts_integration_subtitle", default: "TTS will also be available through the local server layer.") }
        static var developerTTSProbeTitle: String { tr("settings.developer_tts_probe_title", default: "Speak Probe") }
        static var developerTTSProbeSubtitle: String { tr("settings.developer_tts_probe_subtitle", default: "Type a line and trigger the speaking chip without waiting for an external caller.") }
        static var developerTTSProbePlaceholder: String { tr("settings.developer_tts_probe_placeholder", default: "Enter debug speech text") }
        static var developerTTSProbePlay: String { tr("settings.developer_tts_probe_play", default: "Speak") }
        static var developerTTSProbeStop: String { tr("settings.developer_tts_probe_stop", default: "Stop") }
        static var serverRuntimeTitle: String { tr("settings.server_runtime_title", default: "Server Runtime") }
        static var serverRuntimeSubtitle: String { tr("settings.server_runtime_subtitle", default: "Expose Tsutae capabilities to local tools and external clients.") }
        static var serverCapabilitiesTitle: String { tr("settings.server_capabilities_title", default: "Capabilities") }
        static var serverCapabilitiesSubtitle: String { tr("settings.server_capabilities_subtitle", default: "Choose what the local server can provide.") }
        static var serverAccessTitle: String { tr("settings.server_access_title", default: "Access") }
        static var serverAccessSubtitle: String { tr("settings.server_access_subtitle", default: "Authentication, endpoints, and request control.") }
        static var serverHooksTitle: String { tr("settings.server_hooks_title", default: "Hooks") }
        static var serverHooksSubtitle: String { tr("settings.server_hooks_subtitle", default: "Useful for callback-based integrations and automation.") }
        static var serverHealthTitle: String { tr("settings.server_health_title", default: "Health") }
        static var serverHealthSubtitle: String { tr("settings.server_health_subtitle", default: "Operational visibility for the service layer.") }
        static var permissionsMicrophoneTitle: String { tr("settings.permissions_microphone_title", default: "Microphone") }
        static var permissionsMicrophoneSubtitle: String { tr("settings.permissions_microphone_subtitle", default: "Required for recording") }
        static var permissionsSpeechRecognitionTitle: String { tr("settings.permissions_speech_recognition_title", default: "Speech Recognition") }
        static var permissionsSpeechRecognitionSubtitle: String { tr("settings.permissions_speech_recognition_subtitle", default: "Required for Apple Speech fallback") }
        static var permissionsAccessibilityTitle: String { tr("settings.permissions_accessibility_title", default: "Accessibility") }
        static var permissionsAccessibilitySubtitle: String { tr("settings.permissions_accessibility_subtitle", default: "Required to insert into the focused app") }
        static var permissionsNotificationsTitle: String { tr("settings.permissions_notifications_title", default: "Notifications") }
        static var permissionsNotificationsSubtitle: String { tr("settings.permissions_notifications_subtitle", default: "Optional for status feedback") }
        static var permissionGrant: String { tr("settings.permission_grant", default: "Grant") }
        static var permissionAllowed: String { tr("settings.permission_allowed", default: "Allowed") }
        static var permissionNeedsAccess: String { tr("settings.permission_needs_access", default: "Needs Access") }
        static var developerWarmupGateTitle: String { tr("settings.developer_warmup_gate_title", default: "Warmup Gate") }
        static var developerWarmupGateSubtitle: String { tr("settings.developer_warmup_gate_subtitle", default: "Reproduce the first-use local model wait state without relying on timing luck.") }
        static var developerWarming: String { tr("settings.developer_warming", default: "Warming") }
        static var developerWarmGateLabel: String { tr("settings.developer_warm_gate_label", default: "Warm Gate") }
        static var developerWarmGateArmed: String { tr("settings.developer_warm_gate_armed", default: "Armed") }
        static var developerWarmGateIdle: String { tr("settings.developer_warm_gate_idle", default: "Idle") }
        static var developerTestWarmGate: String { tr("settings.developer_test_warm_gate", default: "Test Warm Gate") }
        static var developerRefreshDiskState: String { tr("settings.developer_refresh_disk_state", default: "Refresh Disk State") }
        static var developerHowToTestTitle: String { tr("settings.developer_how_to_test_title", default: "How to Test") }
        static var developerHowToTestSubtitle: String { tr("settings.developer_how_to_test_subtitle", default: "Use the button below, then trigger the capsule immediately.") }
        static var developerHowToTestStep1: String { tr("settings.developer_how_to_test_step1", default: "Keep Local First on") }
        static var developerHowToTestStep2: String { tr("settings.developer_how_to_test_step2", default: "Click Test Warm Gate") }
        static var developerHowToTestStep3: String { tr("settings.developer_how_to_test_step3", default: "Trigger the capsule right away") }
        static var developerHowToTestExpectedLabel: String { tr("settings.developer_how_to_test_expected_label", default: "Expected") }
        static var developerHowToTestExpected: String { tr("settings.developer_how_to_test_expected", default: "Companion appears first, then Listen") }
        static var sttLocalSectionTitle: String { tr("settings.stt_local_section_title", default: "Local") }
        static var sttLocalSectionSubtitle: String { tr("settings.stt_local_section_subtitle", default: "On-device transcription models, downloads, and default model choice are managed in a separate page.") }
        static func sttDownloadedCount(_ count: Int) -> String {
            String(format: tr("settings.stt_downloaded_count_format", default: "%d Downloaded"), count)
        }
        static var sttSelectedModelLabel: String { tr("settings.stt_selected_model_label", default: "Selected Model") }
        static var sttLibraryLabel: String { tr("settings.stt_library_label", default: "Library") }
        static var sttDownloadedLabel: String { tr("settings.stt_downloaded_label", default: "Downloaded") }
        static var sttNextStepLabel: String { tr("settings.stt_next_step_label", default: "Next Step") }
        static var sttManageModelsValue: String { tr("settings.stt_manage_models_value", default: "Manage filters, downloads, and selection") }
        static var sttManageModelsButton: String { tr("settings.stt_manage_models_button", default: "Manage Models") }
        static var sttRefreshButton: String { tr("settings.stt_refresh_button", default: "Refresh") }
        static func sttWarmingModel(_ modelName: String) -> String {
            String(format: tr("settings.stt_warming_model_format", default: "Warming %@…"), modelName)
        }
        static var sttBackToSTT: String { tr("settings.stt_back_to_stt", default: "Back to STT") }
        static var sttLocalModelsTitle: String { tr("settings.stt_local_models_title", default: "Local Models") }
        static var sttLocalModelsSubtitle: String { tr("settings.stt_local_models_subtitle", default: "Browse the on-device library here. Use Downloaded to quickly filter what is already on this Mac. Rough size and RAM numbers are planning values for now; later we will replace them with measured values.") }
        static var sttModelLibraryTitle: String { tr("settings.stt_model_library_title", default: "Model Library") }
        static var sttModelLibrarySubtitle: String { tr("settings.stt_model_library_subtitle", default: "Filter, download, and choose the default local model used by Local First.") }
        static var sttSelectedLabel: String { tr("settings.stt_selected_label", default: "Selected") }
        static var sttAvailableLabel: String { tr("settings.stt_available_label", default: "Available") }
        static var sttPrimaryModeLabel: String { tr("settings.stt_primary_mode_label", default: "Primary Mode") }
        static func sttCuratedModelsCount(_ count: Int) -> String {
            String(format: tr("settings.stt_curated_models_count_format", default: "%d curated models"), count)
        }
        static func sttReadyOnThisMacCount(_ count: Int) -> String {
            String(format: tr("settings.stt_ready_on_this_mac_count_format", default: "%d ready on this Mac"), count)
        }
        static func sttReadyCount(_ count: Int) -> String {
            String(format: tr("settings.stt_ready_count_format", default: "%d ready"), count)
        }
        static var sttSearchModelsPlaceholder: String { tr("settings.stt_search_models_placeholder", default: "Search models") }
        static var sttFilterAllModels: String { tr("settings.stt_filter_all_models", default: "All Models") }
        static var sttFilterDownloaded: String { tr("settings.stt_filter_downloaded", default: "Downloaded") }
        static var sttFilterAuto: String { tr("settings.stt_filter_auto", default: "Auto / Mixed") }
        static var sttFilterChinese: String { tr("settings.stt_filter_chinese", default: "Chinese") }
        static var sttFilterEnglish: String { tr("settings.stt_filter_english", default: "English") }
        static var sttFilterPreview: String { tr("settings.stt_filter_preview", default: "Preview / Streaming") }
        static var sttDeleteErrorTitle: String { tr("settings.stt_delete_error_title", default: "Couldn’t Delete Model") }
        static var sttDeleteCurrentTitle: String { tr("settings.stt_delete_current_title", default: "Delete Current Local Model?") }
        static var sttDeleteDownloadedTitle: String { tr("settings.stt_delete_downloaded_title", default: "Delete Downloaded Model?") }
        static var sttDeleteAndSwitchAction: String { tr("settings.stt_delete_and_switch_action", default: "Delete & Switch") }
        static var sttDeleteAction: String { tr("settings.stt_delete_action", default: "Delete") }
        static func sttDeleteCurrentMessage(modelName: String, replacementName: String) -> String {
            String(format: tr("settings.stt_delete_current_message_format", default: "%1$@ is the current default local model. Tsutae will remove its files and switch local selection to %2$@."), modelName, replacementName)
        }
        static func sttDeleteDownloadedMessage(_ modelName: String) -> String {
            String(format: tr("settings.stt_delete_downloaded_message_format", default: "Remove %1$@ from this Mac? You can download it again later."), modelName)
        }
        static var sttCurrentSetupTitle: String { tr("settings.stt_current_setup_title", default: "Current Setup") }
        static var sttCurrentSetupSubtitle: String { tr("settings.stt_current_setup_subtitle", default: "Keep the active chain readable here. Model management lives on its own Local page.") }
        static var sttCurrentLocalModelLabel: String { tr("settings.stt_current_local_model_label", default: "Local Model") }
        static var sttCurrentRemoteModelLabel: String { tr("settings.stt_current_remote_model_label", default: "Remote Model") }
        static var sttNotSetFallback: String { tr("settings.stt_not_set_fallback", default: "Not Set") }
        static var sttModeLabel: String { tr("settings.stt_mode_label", default: "Mode") }
        static var sttModeLocalFirst: String { tr("settings.stt_mode_local_first", default: "Local First") }
        static var sttModeRemoteFirst: String { tr("settings.stt_mode_remote_first", default: "Remote First") }
        static var sttLanguageLabel: String { tr("settings.stt_language_label", default: "Language") }
        static var sttLanguageAutoDetectLong: String { tr("settings.stt_language_auto_detect_long", default: "Auto detect · zh / en") }
        static var sttLanguageAutoDetectBadge: String { tr("settings.stt_language_auto_detect_badge", default: "Auto Detect") }
        static var sttKeepLocalWarmedTitle: String { tr("settings.stt_keep_local_warmed_title", default: "Keep Local Warmed in Remote First") }
        static var sttKeepLocalWarmedSubtitle: String { tr("settings.stt_keep_local_warmed_subtitle", default: "Advanced. Keep the selected local model loaded even when remote is the preferred STT route.") }
        static var sttKeepWarmBadge: String { tr("settings.stt_keep_warm_badge", default: "Keep Warm") }
        static var sttUnloadWhenIdleBadge: String { tr("settings.stt_unload_when_idle_badge", default: "Unload When Idle") }
        static var sttRemoteSectionTitle: String { tr("settings.stt_remote_section_title", default: "Remote API") }
        static var sttRemoteSectionSubtitle: String { tr("settings.stt_remote_section_subtitle", default: "Optional remote STT. Choose the protocol your provider expects, then test and save.") }
        static var sttRemoteUseTitle: String { tr("settings.stt_remote_use_title", default: "Use Remote") }
        static var sttRemoteUseEnabledSubtitle: String { tr("settings.stt_remote_use_enabled_subtitle", default: "Optional HTTP endpoint for STT routing.") }
        static var sttRemoteUseDisabledSubtitle: String { tr("settings.stt_remote_use_disabled_subtitle", default: "Off by default. Turn it on only when you actually want a remote endpoint.") }
        static var sttRemoteConnectionTitle: String { tr("settings.stt_remote_connection_title", default: "Connection") }
        static var sttRemoteProtocolLabel: String { tr("settings.stt_remote_protocol_label", default: "Protocol") }
        static var sttRemoteProtocolTranscriptions: String { tr("settings.stt_remote_protocol_transcriptions", default: "OpenAI Transcriptions") }
        static var sttRemoteProtocolChatAudio: String { tr("settings.stt_remote_protocol_chat_audio", default: "Chat Completions Audio") }
        static var sttRemoteBaseURLLabel: String { tr("settings.stt_remote_base_url_label", default: "Base URL") }
        static var sttRemoteModelLabel: String { tr("settings.stt_remote_model_label", default: "Model") }
        static var sttRemoteAPIKeyLabel: String { tr("settings.stt_remote_api_key_label", default: "API Key") }
        static var sttRemoteBaseURLPlaceholder: String { tr("settings.stt_remote_base_url_placeholder", default: "https://api.example.com or http://127.0.0.1:1337") }
        static var sttRemoteModelPlaceholder: String { tr("settings.stt_remote_model_placeholder", default: "Enter model id") }
        static var sttRemoteAPIKeyStoredPlaceholder: String { tr("settings.stt_remote_api_key_stored_placeholder", default: "Stored in Keychain") }
        static var sttRemoteAPIKeyHelp: String { tr("settings.stt_remote_api_key_help", default: "Tsutae stores your API key in macOS Keychain, not in the config file. After the first successful read in this app launch, it is kept in memory so recording does not keep asking Keychain again.") }
        static var sttRemoteProtocolHelpTranscriptions: String { tr("settings.stt_remote_protocol_help_transcriptions", default: "Multipart file upload on /audio/transcriptions. Best for OpenAI, LiteLLM, and most local Whisper-style servers.") }
        static var sttRemoteProtocolHelpChatAudio: String { tr("settings.stt_remote_protocol_help_chat_audio", default: "JSON audio input on /chat/completions. Use this when the provider accepts audio inside chat messages instead of file upload.") }
        static var sttRemoteTestButton: String { tr("settings.stt_remote_test_button", default: "Test") }
        static var sttRemoteCheckingButton: String { tr("settings.stt_remote_checking_button", default: "Checking…") }
        static var sttRemoteSaveButton: String { tr("settings.stt_remote_save_button", default: "Save") }
        static var sttRemoteFeedbackChecking: String { tr("settings.stt_remote_feedback_checking", default: "Checking endpoint…") }
        static var sttRemoteFeedbackTestPassed: String { tr("settings.stt_remote_feedback_test_passed", default: "Test passed · ready to save") }
        static var sttRemoteFeedbackEdited: String { tr("settings.stt_remote_feedback_edited", default: "Edited · test current values before saving") }
        static var sttRemoteFeedbackSaved: String { tr("settings.stt_remote_feedback_saved", default: "Saved") }
        static var sttRemoteFeedbackSavedConfiguration: String { tr("settings.stt_remote_feedback_saved_configuration", default: "Saved configuration") }
        static var sttRemoteFeedbackNotTested: String { tr("settings.stt_remote_feedback_not_tested", default: "Not tested") }
        static var sttRemoteErrorInvalidBaseURL: String { tr("settings.stt_remote_error_invalid_base_url", default: "Enter a valid base URL first") }
        static var sttRemoteErrorModelRequired: String { tr("settings.stt_remote_error_model_required", default: "Enter a model first") }
        static var sttRemoteTranscriptionOK: String { tr("settings.stt_remote_transcription_ok", default: "Transcription OK") }
        static func sttRemoteTranscriptionOKWithText(_ text: String) -> String {
            String(format: tr("settings.stt_remote_transcription_ok_with_text_format", default: "Transcription OK · %@"), text)
        }
        static var sttFallbackSectionTitle: String { tr("settings.stt_fallback_section_title", default: "Fallback") }
        static var sttFallbackSectionSubtitle: String { tr("settings.stt_fallback_section_subtitle", default: "Optional backup via Apple Speech.") }
        static var sttFallbackAppleSpeechTitle: String { tr("settings.stt_fallback_apple_speech_title", default: "Apple Speech Fallback") }
        static var sttFallbackAppleSpeechSubtitle: String { tr("settings.stt_fallback_apple_speech_subtitle", default: "Use Apple Speech only when the primary STT chain fails.") }
        static var sttFallbackAppleSpeechValue: String { tr("settings.stt_fallback_apple_speech_value", default: "Apple Speech") }
        static var sttDisabledValue: String { tr("settings.stt_disabled_value", default: "Disabled") }
        static var sttFallbackOn: String { tr("settings.stt_fallback_on", default: "Fallback On") }
        static var sttNoFallback: String { tr("settings.stt_no_fallback", default: "No Fallback") }
        static var sttRemoteOff: String { tr("settings.stt_remote_off", default: "Remote Off") }
        static var sttRemoteReady: String { tr("settings.stt_remote_ready", default: "Remote Ready") }
        static var sttNeedsSetup: String { tr("settings.stt_needs_setup", default: "Needs Setup") }
        static var sttOffShort: String { tr("settings.stt_off_short", default: "Off") }
        static var sttReadyShort: String { tr("settings.stt_ready_short", default: "Ready") }
        static var sttNotSelectedFallback: String { tr("settings.stt_not_selected_fallback", default: "Not Selected") }
        static var sttAnotherModelFallback: String { tr("settings.stt_another_model_fallback", default: "another model") }
        static var sttModelStatusWarmingLocal: String { tr("settings.stt_model_status_warming_local", default: "Warming local model…") }
        static var sttModelStatusNotDownloaded: String { tr("settings.stt_model_status_not_downloaded", default: "Not downloaded") }
        static var sttModelStatusPreparingFiles: String { tr("settings.stt_model_status_preparing_files", default: "Preparing files…") }
        static var sttModelStatusDefaultLocalModel: String { tr("settings.stt_model_status_default_local_model", default: "Default local model") }
        static var sttModelStatusReady: String { tr("settings.stt_model_status_ready", default: "Ready") }
        static var sttModelStatusRetryDownload: String { tr("settings.stt_model_status_retry_download", default: "Retry download") }
        static var sttModelGroupMixed: String { tr("settings.stt_model_group_mixed", default: "Mixed") }
        static var sttModelGroupChinese: String { tr("settings.stt_model_group_chinese", default: "Chinese") }
        static var sttModelGroupEnglish: String { tr("settings.stt_model_group_english", default: "English") }
        static var sttModelGroupPreview: String { tr("settings.stt_model_group_preview", default: "Preview") }
        static var sttModelTopPick: String { tr("settings.stt_model_top_pick", default: "Top Pick") }
        static var sttModelSummarySenseVoiceSmall: String { tr("settings.stt_model_summary_sensevoice_small", default: "Balanced local model for mixed Chinese and English speech.") }
        static var sttModelSummaryQwen3ASRInt8: String { tr("settings.stt_model_summary_qwen3_asr_int8", default: "Mixed-language option with better coverage but slower runtime.") }
        static var sttModelSummaryParaformerLargeZH: String { tr("settings.stt_model_summary_paraformer_large_zh", default: "Fast local model tuned for Chinese transcription.") }
        static var sttModelSummaryParakeetCTCChinese: String { tr("settings.stt_model_summary_parakeet_ctc_chinese", default: "Mandarin-focused CoreML path with weaker text spacing output.") }
        static var sttModelSummaryParakeetTDTV3: String { tr("settings.stt_model_summary_parakeet_tdt_v3", default: "Fast 0.6B model for English and other European languages.") }
        static var sttModelSummaryParakeetEOU: String { tr("settings.stt_model_summary_parakeet_eou", default: "Preview-only streaming candidate for future partial transcription.") }
        static var sttModelTagBestForMixed: String { tr("settings.stt_model_tag_best_for_mixed", default: "Best for Mixed") }
        static var sttModelTagBalanced: String { tr("settings.stt_model_tag_balanced", default: "Balanced") }
        static var sttModelTagLowMemory: String { tr("settings.stt_model_tag_low_memory", default: "Low Memory") }
        static var sttModelTagMixedLanguage: String { tr("settings.stt_model_tag_mixed_language", default: "Mixed Language") }
        static var sttModelTagHigherMemory: String { tr("settings.stt_model_tag_higher_memory", default: "Higher Memory") }
        static var sttModelTagSlower: String { tr("settings.stt_model_tag_slower", default: "Slower") }
        static var sttModelTagBestForChinese: String { tr("settings.stt_model_tag_best_for_chinese", default: "Best for Chinese") }
        static var sttModelTagChineseFocused: String { tr("settings.stt_model_tag_chinese_focused", default: "Chinese Focused") }
        static var sttModelTagChineseOnly: String { tr("settings.stt_model_tag_chinese_only", default: "Chinese") }
        static var sttModelTagSpacingIssues: String { tr("settings.stt_model_tag_spacing_issues", default: "Spacing Issues") }
        static var sttModelTagBestForEnglish: String { tr("settings.stt_model_tag_best_for_english", default: "Best for English") }
        static var sttModelTagFast: String { tr("settings.stt_model_tag_fast", default: "Fast") }
        static var sttModelTagPreviewOnly: String { tr("settings.stt_model_tag_preview_only", default: "Preview Only") }
        static var sttModelTagBeta: String { tr("settings.stt_model_tag_beta", default: "Beta") }
        static var sttModelBadgeWarming: String { tr("settings.stt_model_badge_warming", default: "Warming") }
        static var sttModelBadgeUsing: String { tr("settings.stt_model_badge_using", default: "Using") }
        static var sttModelBadgeAvailable: String { tr("settings.stt_model_badge_available", default: "Available") }
        static var sttModelBadgeDownloading: String { tr("settings.stt_model_badge_downloading", default: "Downloading") }
        static var sttModelBadgeDownloaded: String { tr("settings.stt_model_badge_downloaded", default: "Downloaded") }
        static var sttModelBadgeRetry: String { tr("settings.stt_model_badge_retry", default: "Retry") }
        static var sttModelActionDownload: String { tr("settings.stt_model_action_download", default: "Download") }
        static var sttModelActionDownloading: String { tr("settings.stt_model_action_downloading", default: "Downloading") }
        static var sttModelActionSetDefault: String { tr("settings.stt_model_action_set_default", default: "Set Default") }
        static var sttModelActionRetry: String { tr("settings.stt_model_action_retry", default: "Retry") }
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
