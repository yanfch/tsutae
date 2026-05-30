import SwiftUI
import TsutaeCore
import OSLog

/// tsutae 主应用入口
@main
struct TsutaeApp: App {
    
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private let logger = Logger(subsystem: "dev.yanfch.Tsutae", category: "MenuBar")
    
    var body: some Scene {
        MenuBarExtra("tsutae", systemImage: "mic.fill") {
            Button("切换录音条") {
                logger.info("Menu action: toggle recording bar")
                DispatchQueue.main.async {
                    FloatingRecordingBar.shared.toggle()
                }
            }
            
            Divider()
            
            SettingsLink {
                Text("设置…")
            }
            .keyboardShortcut(",", modifiers: .command)
            
            Divider()
            
            Button("退出 tsutae") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .menuBarExtraStyle(.menu)
        
        Settings {
            SettingsView()
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    
    private var escapeMonitor: Any?
    private let logger = Logger(subsystem: "dev.yanfch.Tsutae", category: "AppDelegate")
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("applicationDidFinishLaunching")
        setupHotkeys()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        if let m = escapeMonitor { NSEvent.removeMonitor(m) }
        GlobalHotkeyManager.shared.stop()
    }
    
    /// 注册全局快捷键
    private func setupHotkeys() {
        logger.info("Registering global hotkey")
        GlobalHotkeyManager.shared.start {
            self.logger.info("Global hotkey fired")
            DispatchQueue.main.async {
                FloatingRecordingBar.shared.toggle()
            }
        }
        
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53, FloatingRecordingBar.shared.isShowing {
                self.logger.info("Escape pressed while recording bar is visible")
                FloatingRecordingBar.shared.hide()
                return nil
            }
            
            return event
        }
    }
}

// MARK: - 设置窗口

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("通用", systemImage: "gear") }
            Text("STT 设置")
                .tabItem { Label("STT", systemImage: "waveform") }
            Text("TTS 设置")
                .tabItem { Label("TTS", systemImage: "speaker.wave.2") }
            Text("快捷键设置")
                .tabItem { Label("快捷键", systemImage: "keyboard") }
            Text("配方设置")
                .tabItem { Label("配方", systemImage: "doc.text") }
        }
        .frame(width: 500, height: 400)
        .background {
            SettingsWindowBridge()
        }
    }
}

private struct SettingsWindowBridge: NSViewRepresentable {
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        
        DispatchQueue.main.async {
            bringWindowToFront(for: view)
        }
        
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            bringWindowToFront(for: nsView)
        }
    }
    
    private func bringWindowToFront(for view: NSView) {
        guard let window = view.window else {
            return
        }
        
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

struct GeneralSettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage(DS.recordingBar.presetDefaultsKey) private var recordingBarPresetRawValue =
        DS.recordingBar.defaultPreset.rawValue
    
    private var recordingBarPreset: Binding<DS.recordingBar.Preset> {
        Binding(
            get: {
                DS.recordingBar.Preset(rawValue: recordingBarPresetRawValue) ?? .compact
            },
            set: { newValue in
                recordingBarPresetRawValue = newValue.rawValue
            }
        )
    }
    
    var body: some View {
        Form {
            Section("启动") {
                Toggle("开机自启", isOn: $launchAtLogin)
            }
            Section("录音条") {
                Picker("尺寸", selection: recordingBarPreset) {
                    ForEach(DS.recordingBar.Preset.allCases, id: \.rawValue) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                
                RecordingBarView(state: .listening, preset: recordingBarPreset.wrappedValue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            Section("快捷键") {
                HStack {
                    Text("录音条")
                    Spacer()
                    Text(GlobalHotkeyManager.shared.toggleRecordingBarShortcutDisplay)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("注册状态")
                    Spacer()
                    Text(GlobalHotkeyManager.shared.isToggleRecordingBarEnabled ? "已启用" : "未启用")
                        .foregroundStyle(
                            GlobalHotkeyManager.shared.isToggleRecordingBarEnabled ? .green : .red
                        )
                }
                Text("默认全局快捷键，已支持切到其他应用时呼出。后续可以在这里接快捷键录制器。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("关于") {
                HStack {
                    Text("版本")
                    Spacer()
                    Text(TsutaeConstants.version)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onChange(of: recordingBarPresetRawValue) { _, _ in
            FloatingRecordingBar.shared.reloadIfShowing()
        }
    }
}
