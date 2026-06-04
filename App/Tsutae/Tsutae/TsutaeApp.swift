import SwiftUI
import TsutaeCore
import OSLog

/// tsutae 主应用入口
@main
struct TsutaeApp: App {
    
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private let logger = Logger(subsystem: "dev.yanfch.Tsutae", category: "MenuBar")
    @StateObject private var recordingSession = RecordingSession.shared
    
    var body: some Scene {
        // 使用自定义品牌图标
        MenuBarExtra("tsutae", image: "MenuBarIcon") {
            if let transcript = recordingSession.lastTranscript, !transcript.isEmpty {
                Text(transcript)
                    .lineLimit(3)
                    .font(.caption)
                Button("复制最近转写") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(transcript, forType: .string)
                }
                Divider()
            }
            
            if let error = recordingSession.lastError {
                Text("错误：\(error)")
                    .lineLimit(2)
                    .font(.caption)
                Divider()
            }
            
            Text("快捷键：\(GlobalHotkeyManager.shared.toggleRecordingShortcutDisplay)")
                .foregroundStyle(.secondary)
            
            Button(recordingSession.isRecording ? "停止并转写" : "开始录音") {
                logger.info("Menu action: toggle recording")
                Task { @MainActor in
                    RecordingSession.shared.toggle()
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
            Task { @MainActor in
                RecordingSession.shared.toggle()
            }
        }
        
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53, FloatingRecordingBar.shared.isShowing {
                self.logger.info("Escape pressed while recording bar is visible")
                RecordingSession.shared.cancel()
                return nil
            }
            
            return event
        }
    }
}
