import SwiftUI
import Combine
import TsutaeCore
import OSLog

@MainActor
final class SettingsWindowCoordinator {
    static let shared = SettingsWindowCoordinator()
    var open: ((String?) -> Void)?
    private init() {}
}

@MainActor
final class LocalSTTResidencyCoordinator {
    static let shared = LocalSTTResidencyCoordinator()
    
    private let logger = Logger(subsystem: "dev.yanfch.Tsutae", category: "LocalSTTResidency")
    private var busyCancellable: AnyCancellable?
    private var pendingConfig: Config?
    
    private init() {
        busyCancellable = RecordingSession.shared.$isBusy
            .removeDuplicates()
            .sink { [weak self] isBusy in
                guard let self else { return }
                guard isBusy == false, let pendingConfig = self.pendingConfig else { return }
                self.pendingConfig = nil
                self.apply(config: pendingConfig)
            }
    }
    
    func refreshFromDisk() {
        let config = (try? ConfigLoader.load()) ?? .default
        requestApply(config: config)
    }
    
    func requestApply(config: Config) {
        if RecordingSession.shared.isBusy {
            pendingConfig = config
            logger.info("Deferred local STT residency update until current recording session finishes")
            return
        }
        apply(config: config)
    }
    
    private func apply(config: Config) {
        Task(priority: .utility) {
            do {
                try await ConfiguredSTTRouter.applyLocalModelResidencyPolicy(config: config)
                self.logger.info("Applied local STT residency policy")
            } catch {
                self.logger.error("Failed to apply local STT residency policy: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

/// tsutae 主应用入口
@main
struct TsutaeApp: App {
    
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private let logger = Logger(subsystem: "dev.yanfch.Tsutae", category: "MenuBar")
    @StateObject private var recordingSession = RecordingSession.shared
    @AppStorage(L10n.appLanguageDefaultsKey) private var appLanguage = L10n.AppLanguage.system.rawValue
    
    var body: some Scene {
        // 使用自定义品牌图标
        MenuBarExtra("tsutae", image: "MenuBarIcon") {
            menuContent
                .environment(\.locale, currentLocale)
        }
        .menuBarExtraStyle(.menu)
        
        Window("Settings", id: "settings-window") {
            SettingsWindowRoot(locale: currentLocale)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            SettingsCommands()
        }
    }
    
    private var currentLocale: Locale {
        _ = appLanguage
        return L10n.currentLocale
    }
    
    @ViewBuilder
    private var menuContent: some View {
        if let transcript = recordingSession.lastTranscript, !transcript.isEmpty {
            Text(transcript)
                .lineLimit(3)
                .font(.caption)
            Button(L10n.Menu.copyLatestTranscript) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(transcript, forType: .string)
            }
            Divider()
        }
        
        if let error = recordingSession.lastError {
            Text(L10n.Menu.error(error))
                .lineLimit(2)
                .font(.caption)
            Divider()
        }
        
        Text(L10n.Menu.shortcut(GlobalHotkeyManager.shared.toggleRecordingShortcutDisplay))
            .foregroundStyle(.secondary)
        
        Button(recordingSession.isRecording ? L10n.Menu.stopAndTranscribe : L10n.Menu.startRecording) {
            logger.info("Menu action: toggle recording")
            Task { @MainActor in
                RecordingSession.shared.toggle()
            }
        }
        
        Divider()
        
        OpenSettingsMenuButton()
            .keyboardShortcut(",", modifiers: .command)
        
        Divider()
        
        Button(L10n.Menu.quit) {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}

private struct SettingsWindowRoot: View {
    let locale: Locale
    @Environment(\.openWindow) private var openWindow
    
    var body: some View {
        SettingsView()
            .environment(\.locale, locale)
            .onAppear {
                SettingsWindowCoordinator.shared.open = { tab in
                    if let tab {
                        UserDefaults.standard.set(tab, forKey: "settings.selectedTab")
                    }
                    openWindow(id: "settings-window")
                }
            }
    }
}

private struct OpenSettingsMenuButton: View {
    @Environment(\.openWindow) private var openWindow
    
    var body: some View {
        Button(L10n.Menu.settings) {
            openWindow(id: "settings-window")
        }
    }
}

private struct SettingsCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    
    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button(L10n.Menu.settings) {
                openWindow(id: "settings-window")
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    
    private var localEscapeMonitor: Any?
    private var globalEscapeMonitor: Any?
    private let logger = Logger(subsystem: "dev.yanfch.Tsutae", category: "AppDelegate")
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("applicationDidFinishLaunching")
        _ = LocalSTTResidencyCoordinator.shared
        setupHotkeys()
        LocalSTTResidencyCoordinator.shared.refreshFromDisk()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        if let m = localEscapeMonitor { NSEvent.removeMonitor(m) }
        if let m = globalEscapeMonitor { NSEvent.removeMonitor(m) }
        GlobalHotkeyManager.shared.stop()
    }
    
    /// 注册全局快捷键
    private func setupHotkeys() {
        logger.info("Registering global hotkey")
        GlobalHotkeyManager.shared.start {
            self.logger.info("Global hotkey fired")
            Task { @MainActor in
                RecordingSession.shared.toggle()
            }
        }
        
        localEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if self.handleEscapeKeyEvent(event) {
                return nil
            }
            
            return event
        }
        
        globalEscapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            _ = self.handleEscapeKeyEvent(event)
        }
    }
    
    private func handleEscapeKeyEvent(_ event: NSEvent) -> Bool {
        guard event.keyCode == 53, FloatingRecordingBar.shared.isShowing else {
            return false
        }
        
        logger.info("Escape pressed while recording bar is visible")
        Task { @MainActor in
            RecordingSession.shared.cancel()
        }
        return true
    }
}
