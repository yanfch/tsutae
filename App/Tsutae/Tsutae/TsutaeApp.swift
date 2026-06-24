import SwiftUI
import Combine
import TsutaeCore
import OSLog
import UserNotifications

@MainActor
final class SettingsWindowCoordinator {
    static let shared = SettingsWindowCoordinator()
    var open: ((String?) -> Void)?
    weak var window: NSWindow?
    private init() {}

    var hasVisibleSettingsWindow: Bool {
        if let window, window.isVisible {
            return true
        }
        return NSApp.windows.contains {
            ($0.identifier?.rawValue == "settings-window" || $0.title == "Settings") && $0.isVisible
        }
    }

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
        NSApp.unhide(nil)
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

    func restoreSettingsAfterActivationPolicyChange() {
        bringToFront()
        DispatchQueue.main.async {
            self.bringToFront()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.bringToFront()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            self.bringToFront()
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

@MainActor
final class LocalTTSResidencyCoordinator: ObservableObject {
    static let shared = LocalTTSResidencyCoordinator()

    @Published private(set) var warmingVoiceID: String?
    @Published private(set) var warmProgressByVoiceID: [String: Double] = [:]
    @Published private(set) var readyVoiceIDs: Set<String> = []
    @Published private(set) var lastError: String?

    private let logger = Logger(subsystem: "dev.yanfch.Tsutae", category: "LocalTTSResidency")
    private var warmTask: Task<Void, Never>?
    private var warmRequestID = UUID()

    private init() {}

    func refreshFromDisk() {
        let config = (try? ConfigLoader.load()) ?? .default
        requestApply(config: config)
        refreshReadyState()
    }

    func requestApply(config: Config) {
        guard config.tts.engine == FluidAudioLocalTTSEngine.shared.id, config.tts.local.enabled else {
            warmTask?.cancel()
            warmingVoiceID = nil
            warmProgressByVoiceID.removeAll()
            lastError = nil
            return
        }
        requestWarm(voiceID: config.tts.voice)
    }

    func requestWarm(voiceID: String?) {
        guard let descriptor = LocalTTSModelCatalog.descriptor(voiceID: voiceID) ?? LocalTTSModelCatalog.all.first else {
            return
        }
        let resolvedVoiceID = descriptor.voiceID

        warmTask?.cancel()
        let requestID = UUID()
        warmRequestID = requestID
        warmingVoiceID = resolvedVoiceID
        warmProgressByVoiceID = [resolvedVoiceID: LocalTTSModelCatalog.isCached(id: descriptor.id) ? 0.9 : 0]
        lastError = nil

        warmTask = Task(priority: .utility) { [weak self] in
            do {
                let warmedVoiceID = try await FluidAudioLocalTTSEngine.shared.prewarm(voiceID: resolvedVoiceID) { progress in
                    Task { @MainActor [weak self] in
                        guard let self, self.warmRequestID == requestID, self.warmingVoiceID == resolvedVoiceID else {
                            return
                        }
                        let clamped = max(0, min(progress, 1))
                        let current = self.warmProgressByVoiceID[resolvedVoiceID] ?? 0
                        self.warmProgressByVoiceID[resolvedVoiceID] = max(current, clamped)
                    }
                }
                await MainActor.run {
                    guard let self else { return }
                    guard self.warmRequestID == requestID else { return }
                    self.readyVoiceIDs.insert(warmedVoiceID)
                    self.clearWarmState(voiceID: warmedVoiceID, requestID: requestID)
                    self.logger.info("Applied local TTS residency policy. voice=\(warmedVoiceID, privacy: .public)")
                }
            } catch is CancellationError {
                await MainActor.run {
                    guard let self else { return }
                    self.clearWarmState(voiceID: resolvedVoiceID, requestID: requestID)
                    self.logger.debug("Cancelled local TTS warmup. voice=\(resolvedVoiceID, privacy: .public)")
                }
            } catch {
                if Self.isCancellationLike(error) {
                    await MainActor.run {
                        guard let self else { return }
                        self.clearWarmState(voiceID: resolvedVoiceID, requestID: requestID)
                        self.logger.debug("Cancelled local TTS warmup. voice=\(resolvedVoiceID, privacy: .public)")
                    }
                    return
                }
                await MainActor.run {
                    guard let self else { return }
                    self.clearWarmState(voiceID: resolvedVoiceID, requestID: requestID)
                    self.lastError = error.localizedDescription
                    self.logger.error("Failed to apply local TTS residency policy: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    private static func isCancellationLike(_ error: Error) -> Bool {
        let message = error.localizedDescription
        return message.contains("CancellationError") || message.contains("cancelled") || message.contains("canceled")
    }

    func refreshReadyState() {
        Task(priority: .utility) { [weak self] in
            var ready: Set<String> = []
            for descriptor in LocalTTSModelCatalog.all {
                if await FluidAudioLocalTTSEngine.shared.isVoiceReady(descriptor.voiceID) {
                    ready.insert(descriptor.voiceID)
                }
            }
            await MainActor.run {
                guard let self else { return }
                self.readyVoiceIDs = ready
                if let warmingVoiceID = self.warmingVoiceID, ready.contains(warmingVoiceID) {
                    self.warmingVoiceID = nil
                    self.warmProgressByVoiceID[warmingVoiceID] = nil
                }
            }
        }
    }

    private func clearWarmState(voiceID: String, requestID: UUID) {
        guard warmRequestID == requestID else { return }
        if warmingVoiceID == voiceID {
            warmingVoiceID = nil
        }
        warmProgressByVoiceID[voiceID] = nil
    }
}

enum TTSGeneralPresentationStyle {
    static var current: Config.TTSPresentationStyle {
        fromRecordingBarPresetRawValue(UserDefaults.standard.string(forKey: DS.recordingBar.presetDefaultsKey))
    }

    static func fromRecordingBarPresetRawValue(_ rawValue: String?) -> Config.TTSPresentationStyle {
        switch rawValue {
        case Config.TTSPresentationStyle.minimal.rawValue, DS.recordingBar.Preset.minimal.rawValue:
            return .minimal
        default:
            return .standard
        }
    }

    static func applyCurrent(to config: inout Config.TTSConfig) {
        config.presentationStyle = current
    }

    static func syncConfigDefaultToCurrent(notify: Bool = true) {
        syncConfigDefault(to: current, notify: notify)
    }

    static func syncConfigDefault(toRecordingBarPresetRawValue rawValue: String, notify: Bool = true) {
        syncConfigDefault(to: fromRecordingBarPresetRawValue(rawValue), notify: notify)
    }

    private static func syncConfigDefault(to style: Config.TTSPresentationStyle, notify: Bool) {
        do {
            var config = try ConfigLoader.load()
            guard config.tts.presentationStyle != style else { return }
            config.tts.presentationStyle = style
            try ConfigLoader.save(config)
            guard notify else { return }
            NotificationCenter.default.post(name: .tsutaeConfigDidChange, object: nil, userInfo: ["config": config])
        } catch {
            return
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

        Button(L10n.Menu.github) {
            TsutaeLinks.openGitHubRepository()
        }

        Button(L10n.Menu.reportIssue) {
            TsutaeLinks.openGitHubIssue()
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
                configure(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                configure(window)
            }
        }
    }

    private func configure(_ window: NSWindow) {
        window.identifier = NSUserInterfaceItemIdentifier("settings-window")
        window.isReleasedWhenClosed = false
        SettingsWindowCoordinator.shared.window = window
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
    private var isDuplicateInstance = false
    private let logger = Logger(subsystem: "dev.yanfch.Tsutae", category: "AppDelegate")
    private let appController = DefaultAppController()
    private lazy var httpServer = HTTPServer(controller: appController)
    private var serverTask: Task<Void, Never>?

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard hasRunningInstance() else {
            return
        }
        isDuplicateInstance = true
        logger.warning("Another Tsutae instance is already running; terminating this instance")
        NSApp.terminate(nil)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard isDuplicateInstance == false else {
            return
        }
        logger.info("applicationDidFinishLaunching")
        PerformanceLog.record(category: "AppDelegate", message: "applicationDidFinishLaunching")
        installApplicationIcon()
        AppPresentationController.shared.applyCurrentDockPreference()
        EngineManager.shared.registerTTS(AppleTTSEngine.shared)
        EngineManager.shared.registerTTS(FluidAudioLocalTTSEngine.shared)
        EngineManager.shared.registerTTS(OpenAICompatibleRemoteTTSEngine.shared)
        EngineManager.shared.registerVAD(EnergyVADEngine.shared)
        EngineManager.shared.registerVAD(FluidAudioVADEngine.shared)
        UNUserNotificationCenter.current().delegate = self
        _ = LocalSTTResidencyCoordinator.shared
        _ = LocalTTSResidencyCoordinator.shared
        TTSGeneralPresentationStyle.syncConfigDefaultToCurrent(notify: false)
        setupHotkeys()
        LocalSTTResidencyCoordinator.shared.refreshFromDisk()
        LocalTTSResidencyCoordinator.shared.refreshFromDisk()
        FloatingSpeakingIndicator.shared.startObserving()
        startHTTPServerIfNeeded()
    }

    private func installApplicationIcon() {
        guard let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let image = NSImage(contentsOf: iconURL) else {
            return
        }
        NSApp.applicationIconImage = image
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowCoordinator.shared.openSettings(tab: nil)
        return false
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
            let message = "Global hotkey fired"
            self.logger.info("\(message, privacy: .public)")
            PerformanceLog.record(category: "Hotkey", message: message)
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
                RecordingSession.shared.requestEscapeCancel()
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

    private func hasRunningInstance() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return false
        }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.contains { application in
            application.bundleIdentifier == bundleIdentifier
                && application.processIdentifier != currentPID
                && application.isTerminated == false
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else {
            return
        }
        let userInfo = response.notification.request.content.userInfo
        await MainActor.run {
            openNotificationTarget(from: userInfo)
        }
    }

    @MainActor
    private func openNotificationTarget(from userInfo: [AnyHashable: Any]) {
        if let clickAction = userInfo[TTSNotifyUserInfoKey.clickAction] as? String,
           clickAction == TTSNotifyClickAction.none.rawValue {
            return
        }

        if let openURL = userInfo[TTSNotifyUserInfoKey.openURL] as? String,
           let url = URL(string: openURL),
           NSWorkspace.shared.open(url) {
            return
        }

        if let bundleID = userInfo[TTSNotifyUserInfoKey.activateBundleID] as? String,
           activateApplication(bundleIdentifier: bundleID) {
            return
        }

        SettingsWindowCoordinator.shared.openSettings(tab: nil)
    }

    @MainActor
    private func activateApplication(bundleIdentifier: String) -> Bool {
        if let application = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
            return application.activate(options: [.activateAllWindows])
        }

        guard let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return false
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration)
        return true
    }
}
