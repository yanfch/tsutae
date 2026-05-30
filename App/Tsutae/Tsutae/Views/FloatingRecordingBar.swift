import SwiftUI
import TsutaeCore
import OSLog

/// 悬浮录音条控制器
/// 对应文档: docs/ui-design.md §B（折叠态）
///
/// 使用 NSPanel 实现：
/// - 无边框、不抢焦点
/// - 置顶、点外面不消失
/// - 屏幕中央显示
final class FloatingRecordingBar {
    
    static let shared = FloatingRecordingBar()
    
    private let logger = Logger(subsystem: "dev.yanfch.Tsutae", category: "FloatingRecordingBar")
    private var panel: NSPanel?
    private(set) var isShowing = false
    
    private init() {}
    
    private var layout: DS.recordingBar.Layout {
        DS.recordingBar.current
    }
    
    /// 显示悬浮录音条
    func show() {
        logger.info("show() called. isShowing=\(self.isShowing, privacy: .public)")
        
        if isShowing {
            logger.info("show() ignored because panel is already visible")
            return
        }
        
        NSApp.activate(ignoringOtherApps: true)
        logger.info("App activated for recording bar presentation")
        
        let panel = NSPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: layout.width,
                height: layout.height
            ),
            styleMask: [
                .nonactivatingPanel,   // 不抢焦点
                .borderless,
            ],
            backing: .buffered,
            defer: false
        )
        logger.info("NSPanel created")
        
        // 配置面板属性
        panel.isFloatingPanel = true                    // 置顶
        panel.level = .statusBar                        // 更接近系统 HUD 层级
        panel.hidesOnDeactivate = false                 // 失焦不隐藏
        panel.backgroundColor = .clear                  // 透明背景（让 SwiftUI 画）
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        
        // 对于菜单栏 App，NSScreen.main 可能为空，优先使用鼠标所在屏幕
        if let screen = screenForPresentation() {
            let visibleFrame = screen.visibleFrame
            let x = visibleFrame.midX - (layout.width / 2)
            let y = visibleFrame.midY - (layout.height / 2) - 42
            panel.setFrameOrigin(NSPoint(x: x, y: y))
            logger.info(
                "Panel positioned on visibleFrame=\(String(describing: visibleFrame), privacy: .public) origin=(\(x, privacy: .public), \(y, privacy: .public))"
            )
        } else {
            panel.center()
            logger.info("Panel centered because no screen could be resolved")
        }
        
        // 嵌入 SwiftUI 视图
        let contentView = RecordingBarView(state: .listening, preset: DS.recordingBar.currentPreset)
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(
            x: 0,
            y: 0,
            width: layout.width,
            height: layout.height
        )
        panel.contentView = hostingView
        logger.info("Hosting view attached")
        
        self.panel = panel
        self.isShowing = true
        
        DispatchQueue.main.async {
            panel.orderFrontRegardless()
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            self.logger.info("Panel ordered front on next runloop")
        }
        
        logger.info("show() completed")
    }
    
    /// 隐藏悬浮录音条
    func hide() {
        logger.info("hide() called. hasPanel=\(self.panel != nil, privacy: .public)")
        panel?.orderOut(nil)
        panel = nil
        isShowing = false
        logger.info("hide() completed")
    }
    
    /// 切换显示/隐藏
    func toggle() {
        logger.info("toggle() called. isShowing=\(self.isShowing, privacy: .public)")
        if isShowing {
            hide()
        } else {
            show()
        }
    }
    
    func reloadIfShowing() {
        guard isShowing else { return }
        logger.info("reloadIfShowing() called while visible")
        hide()
        show()
    }
    
    private func screenForPresentation() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        logger.info("Resolving screen for mouseLocation=\(String(describing: mouseLocation), privacy: .public)")
        
        return NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }
}
