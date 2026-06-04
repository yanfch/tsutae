import SwiftUI
import Combine
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
    private let savedOriginXKey = "recordingBar.origin.x"
    private let savedOriginYKey = "recordingBar.origin.y"
    private var panel: NSPanel?
    private var presentationModel: RecordingBarPresentationModel?
    private(set) var isShowing = false
    private var currentState: AppState = .idle
    
    private init() {}
    
    private var layout: DS.recordingBar.Layout {
        DS.recordingBar.current
    }
    
    /// 显示悬浮录音条
    func show(state: AppState = .listening) {
        logger.info("show() called. isShowing=\(self.isShowing, privacy: .public)")
        currentState = state
        
        if isShowing {
            update(state: state)
            return
        }
        
        let panel = DraggableRecordingPanel(
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
        panel.onDragEnded = { [weak self, weak panel] in
            guard let self, let panel else { return }
            self.savePanelOrigin(panel.frame.origin)
        }
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
        
        if let savedOrigin = savedOrigin(for: panel.frame.size) {
            panel.setFrameOrigin(savedOrigin)
            logger.info("Panel restored to saved origin=(\(savedOrigin.x, privacy: .public), \(savedOrigin.y, privacy: .public))")
        } else if let screen = screenForPresentation() {
            // 对于菜单栏 App，NSScreen.main 可能为空，优先使用鼠标所在屏幕。
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
        let appearanceMode = UserDefaults.standard.string(forKey: "settings.appearanceMode") ?? "system"
        let colorScheme = resolvedColorScheme(for: appearanceMode)
        
        if appearanceMode == "light" {
            panel.appearance = NSAppearance(named: .aqua)
        } else if appearanceMode == "dark" {
            panel.appearance = NSAppearance(named: .darkAqua)
        } else {
            panel.appearance = nil
        }
        
        let presentationModel = RecordingBarPresentationModel(
            state: state,
            preset: DS.recordingBar.currentPreset,
            colorScheme: colorScheme
        )
        self.presentationModel = presentationModel
        
        let wrapperView = RecordingBarWrapper(model: presentationModel)
        let hostingView = NSHostingView(rootView: wrapperView)
        hostingView.frame = NSRect(
            x: 0,
            y: 0,
            width: layout.width,
            height: layout.height
        )
        // 设置 NSHostingView 背景为透明，让 SwiftUI 视图自己绘制背景
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView
        logger.info("Hosting view attached")
        
        self.panel = panel
        self.isShowing = true
        
        DispatchQueue.main.async {
            panel.orderFrontRegardless()
            self.logger.info("Panel ordered front without activating app")
        }
        
        logger.info("show() completed")
    }
    
    func update(state: AppState) {
        currentState = state
        
        guard isShowing else {
            show(state: state)
            return
        }
        
        guard let presentationModel else {
            logger.error("Failed to update recording bar because presentation model is missing")
            return
        }
        
        let appearanceMode = UserDefaults.standard.string(forKey: "settings.appearanceMode") ?? "system"
        let colorScheme = resolvedColorScheme(for: appearanceMode)
        
        withAnimation(.easeInOut(duration: 0.24)) {
            presentationModel.state = state
            presentationModel.preset = DS.recordingBar.currentPreset
            presentationModel.colorScheme = colorScheme
        }
        logger.info("Recording bar state updated to \(state.rawValue, privacy: .public)")
    }
    
    /// 隐藏悬浮录音条
    func hide() {
        logger.info("hide() called. hasPanel=\(self.panel != nil, privacy: .public)")
        panel?.orderOut(nil)
        panel = nil
        presentationModel = nil
        isShowing = false
        currentState = .idle
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
        let state = currentState
        hide()
        show(state: state)
    }
    
    private func resolvedColorScheme(for appearanceMode: String) -> ColorScheme {
        switch appearanceMode {
        case "light":
            return .light
        case "dark":
            return .dark
        default:
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? .dark : .light
        }
    }
    
    private func screenForPresentation() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        logger.info("Resolving screen for mouseLocation=\(String(describing: mouseLocation), privacy: .public)")
        
        return NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }
    
    private func savedOrigin(for panelSize: NSSize) -> NSPoint? {
        let defaults = UserDefaults.standard
        
        guard
            defaults.object(forKey: savedOriginXKey) != nil,
            defaults.object(forKey: savedOriginYKey) != nil
        else {
            return nil
        }
        
        let origin = NSPoint(
            x: defaults.double(forKey: savedOriginXKey),
            y: defaults.double(forKey: savedOriginYKey)
        )
        
        let frame = NSRect(origin: origin, size: panelSize)
        guard NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) else {
            return nil
        }
        
        return origin
    }
    
    private func savePanelOrigin(_ origin: NSPoint) {
        UserDefaults.standard.set(origin.x, forKey: savedOriginXKey)
        UserDefaults.standard.set(origin.y, forKey: savedOriginYKey)
        logger.info("Panel origin saved=(\(origin.x, privacy: .public), \(origin.y, privacy: .public))")
    }
}

private final class DraggableRecordingPanel: NSPanel {
    
    var onDragEnded: (() -> Void)?
    
    private var dragStartLocation: NSPoint?
    private var dragStartOrigin: NSPoint?
    
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    
    override func mouseDown(with event: NSEvent) {
        dragStartLocation = NSEvent.mouseLocation
        dragStartOrigin = frame.origin
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard
            let dragStartLocation,
            let dragStartOrigin
        else {
            return
        }
        
        let currentLocation = NSEvent.mouseLocation
        let deltaX = currentLocation.x - dragStartLocation.x
        let deltaY = currentLocation.y - dragStartLocation.y
        
        setFrameOrigin(NSPoint(
            x: dragStartOrigin.x + deltaX,
            y: dragStartOrigin.y + deltaY
        ))
    }
    
    override func mouseUp(with event: NSEvent) {
        dragStartLocation = nil
        dragStartOrigin = nil
        onDragEnded?()
    }
}

// MARK: - RecordingBarWrapper

@MainActor
private final class RecordingBarPresentationModel: ObservableObject {
    @Published var state: AppState
    @Published var preset: DS.recordingBar.Preset
    @Published var colorScheme: ColorScheme
    
    init(state: AppState, preset: DS.recordingBar.Preset, colorScheme: ColorScheme) {
        self.state = state
        self.preset = preset
        self.colorScheme = colorScheme
    }
}

/// 包装 RecordingBarView，确保背景正确渲染
private struct RecordingBarWrapper: View {
    @ObservedObject var model: RecordingBarPresentationModel
    
    var body: some View {
        RecordingBarView(
            state: model.state,
            preset: model.preset,
            colorScheme: model.colorScheme
        )
    }
}
