import SwiftUI
import Combine
import TsutaeCore
import OSLog

@MainActor
final class SettingsWindowCoordinator {
    static let shared = SettingsWindowCoordinator()
    var open: ((String?) -> Void)?
    weak var window: NSWindow?
    private init() {}
    
    func openSettings(tab: String?) {
        if let tab {
            UserDefaults.standard.set(tab, forKey: "settings.selectedTab")
        }
        NSApp.activate(ignoringOtherApps: true)
        if let open {
            open(tab)
        } else {
            _ = NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.bringToFront()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            self.bringToFront()
        }
    }
    
    func bringToFront() {
        NSApp.activate(ignoringOtherApps: true)
        if let window {
            window.identifier = NSUserInterfaceItemIdentifier("settings-window")
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }
        if let fallback = NSApp.windows.first(where: { $0.identifier?.rawValue == "settings-window" || $0.title == "Settings" }) {
            self.window = fallback
            fallback.makeKeyAndOrderFront(nil)
            fallback.orderFrontRegardless()
        }
    }
}

@MainActor
final class LocalSTTResidencyCoordinator: ObservableObject {
    static let shared = LocalSTTResidencyCoordinator()
    
    @Published private(set) var warmingModelID: String?
    
    private let logger = Logger(subsystem: "dev.yanfch.Tsutae", category: "LocalSTTResidency")
    private var busyCancellable: AnyCancellable?
    private var pendingConfig: Config?
    private var debugNextWarmupDelay: Duration?
    
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
    
    func requiresWarmupGate(config: Config) async -> Bool {
        guard config.stt.mode == .localFirst else { return false }
        guard let modelID = config.stt.local.preferredModel ?? config.stt.model, modelID.isEmpty == false else { return false }
        guard LocalSTTModelCatalog.isDownloaded(id: modelID) else { return false }
        if warmingModelID == modelID {
            return true
        }
        return await FluidAudioSTT.isModelReady(modelID) == false
    }
    
    func waitUntilLocalModelReady(config: Config) async throws {
        guard config.stt.mode == .localFirst else { return }
        guard let modelID = config.stt.local.preferredModel ?? config.stt.model, modelID.isEmpty == false else { return }
        warmingModelID = modelID
        let debugDelay = debugNextWarmupDelay
        debugNextWarmupDelay = nil
        defer {
            if warmingModelID == modelID {
                warmingModelID = nil
            }
        }
        if let debugDelay {
            try await Task.sleep(for: debugDelay)
        }
        try await ConfiguredSTTRouter.prewarmLocalModel(config: config)
    }
    
    func prepareWarmupGateTest(config: Config, delay: Duration = .seconds(5)) {
        guard let modelID = config.stt.local.preferredModel ?? config.stt.model, modelID.isEmpty == false else { return }
        debugNextWarmupDelay = delay
        warmingModelID = nil
        Task(priority: .utility) {
            do {
                try await ConfiguredSTTRouter.unloadLocalModel(config: config)
                await MainActor.run {
                    self.logger.info("Prepared local STT warmup gate test. model=\(modelID, privacy: .public)")
                }
            } catch {
                await MainActor.run {
                    self.logger.error("Failed to prepare warmup gate test: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }
    
    private func apply(config: Config) {
        let modelID = config.stt.local.preferredModel ?? config.stt.model
        let shouldWarm = config.stt.mode == .localFirst || config.stt.local.keepModelWarmedInRemoteFirst
        
        if shouldWarm {
            warmingModelID = modelID
        } else {
            warmingModelID = nil
        }
        
        Task(priority: .utility) {
            do {
                try await ConfiguredSTTRouter.applyLocalModelResidencyPolicy(config: config)
                await MainActor.run {
                    if self.warmingModelID == modelID {
                        self.warmingModelID = nil
                    }
                    self.logger.info("Applied local STT residency policy")
                }
            } catch {
                await MainActor.run {
                    if self.warmingModelID == modelID {
                        self.warmingModelID = nil
                    }
                    self.logger.error("Failed to apply local STT residency policy: \(error.localizedDescription, privacy: .public)")
                }
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
        MenuBarExtra("Tsutae", image: "MenuBarIcon") {
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
        MenuBarMenuContent(recordingSession: recordingSession, logger: logger)
    }
}

private struct MenuBarMenuContent: View {
    @ObservedObject var recordingSession: RecordingSession
    @ObservedObject private var hotkeyManager = GlobalHotkeyManager.shared
    let logger: Logger
    
    var body: some View {
        Button(recordingSession.isRecording ? L10n.Menu.stopAndTranscribe : L10n.Menu.startRecording) {
            logger.info("Menu action: toggle recording")
            Task { @MainActor in
                RecordingSession.shared.toggle()
            }
        }
        
        if let transcript = recordingSession.lastTranscript, !transcript.isEmpty {
            Button(L10n.Menu.copyLatestTranscript) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(transcript, forType: .string)
            }
        }
        
        Divider()
        
        Text(L10n.Menu.shortcut(hotkeyManager.toggleRecordingShortcutDisplay))
            .foregroundStyle(.secondary)
        
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
            .background(SettingsWindowAccessor())
            .onAppear {
                SettingsWindowCoordinator.shared.open = { _ in
                    openWindow(id: "settings-window")
                }
            }
    }
}

private struct SettingsWindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.identifier = NSUserInterfaceItemIdentifier("settings-window")
                SettingsWindowCoordinator.shared.window = window
            }
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                window.identifier = NSUserInterfaceItemIdentifier("settings-window")
                SettingsWindowCoordinator.shared.window = window
            }
        }
    }
}

private struct OpenSettingsMenuButton: View {
    var body: some View {
        Button(L10n.Menu.settings) {
            SettingsWindowCoordinator.shared.openSettings(tab: nil)
        }
    }
}

private struct SettingsCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    
    var body: some Commands {
        let _ = installOpenHandler()
        CommandGroup(replacing: .appSettings) {
            Button(L10n.Menu.settings) {
                SettingsWindowCoordinator.shared.openSettings(tab: nil)
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
    
    private func installOpenHandler() {
        SettingsWindowCoordinator.shared.open = { _ in
            openWindow(id: "settings-window")
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    
    private var localEscapeMonitor: Any?
    private var globalEscapeMonitor: Any?
    private let logger = Logger(subsystem: "dev.yanfch.Tsutae", category: "AppDelegate")
    private let appController = DefaultAppController()
    private lazy var httpServer = HTTPServer(controller: appController)
    private var serverTask: Task<Void, Never>?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("applicationDidFinishLaunching")
        EngineManager.shared.registerTTS(AppleTTSEngine.shared)
        _ = LocalSTTResidencyCoordinator.shared
        setupHotkeys()
        LocalSTTResidencyCoordinator.shared.refreshFromDisk()
        FloatingSpeakingIndicator.shared.startObserving()
        startHTTPServerIfNeeded()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        if let m = localEscapeMonitor { NSEvent.removeMonitor(m) }
        if let m = globalEscapeMonitor { NSEvent.removeMonitor(m) }
        GlobalHotkeyManager.shared.stop()
        serverTask?.cancel()
        httpServer.stop()
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
        guard event.keyCode == 53 else {
            return false
        }
        
        if FloatingRecordingBar.shared.isShowing {
            logger.info("Escape pressed while recording bar is visible")
            Task { @MainActor in
                RecordingSession.shared.cancel()
            }
            return true
        }
        
        if TTSPlaybackManager.shared.isSpeaking {
            logger.info("Escape pressed while speaking indicator is active")
            TTSPlaybackManager.shared.stop()
            return true
        }
        
        return false
    }
    
    private func startHTTPServerIfNeeded() {
        let config = (try? ConfigLoader.load()) ?? .default
        guard config.server.autoStart else {
            logger.info("HTTP server auto-start disabled")
            return
        }
        serverTask?.cancel()
        serverTask = Task(priority: .utility) { [logger, httpServer] in
            do {
                logger.info("Starting HTTP server on \(config.server.bind, privacy: .public):\(config.server.port, privacy: .public)")
                try await httpServer.start(host: config.server.bind, port: config.server.port)
            } catch is CancellationError {
                logger.info("HTTP server task cancelled")
            } catch {
                logger.error("Failed to start HTTP server: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
