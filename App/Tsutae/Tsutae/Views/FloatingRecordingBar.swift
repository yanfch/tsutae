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
    private var hostingView: NSHostingView<RecordingBarWrapper>?
    private var presentationModel: RecordingBarPresentationModel?
    private var companionDismissWorkItem: DispatchWorkItem?
    private(set) var isShowing = false
    private var currentState: AppState = .idle
    
    private init() {}
    
    private let panelHorizontalInset: CGFloat = 12
    private let panelVerticalInset: CGFloat = 10
    private let companionSpacing: CGFloat = 10
    private let companionHeight: CGFloat = 122
    private let companionMinWidth: CGFloat = 360
    
    private var layout: DS.recordingBar.Layout {
        DS.recordingBar.current
    }
    
    private var panelContentWidth: CGFloat {
        max(layout.width, companionMinWidth)
    }
    
    private var barContainerSize: NSSize {
        NSSize(
            width: layout.width + (panelHorizontalInset * 2),
            height: layout.height + (panelVerticalInset * 2)
        )
    }
    
    private var panelSize: NSSize {
        NSSize(
            width: panelContentWidth + (panelHorizontalInset * 2),
            height: barContainerSize.height + companionSpacing + companionHeight
        )
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
                width: panelSize.width,
                height: panelSize.height
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
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        
        if let savedOrigin = savedOrigin(for: panel.frame.size) {
            panel.setFrameOrigin(savedOrigin)
            logger.info("Panel restored to saved origin=(\(savedOrigin.x, privacy: .public), \(savedOrigin.y, privacy: .public))")
        } else if let screen = screenForPresentation() {
            // 对于菜单栏 App，NSScreen.main 可能为空，优先使用鼠标所在屏幕。
            let visibleFrame = screen.visibleFrame
            let x = visibleFrame.midX - (barContainerSize.width / 2)
            let y = visibleFrame.midY - (barContainerSize.height / 2) - 42 - (panelSize.height - barContainerSize.height)
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
            displayState: visualState(for: state),
            preset: DS.recordingBar.currentPreset,
            colorScheme: colorScheme
        )
        self.presentationModel = presentationModel
        
        let wrapperView = RecordingBarWrapper(
            model: presentationModel,
            horizontalInset: panelHorizontalInset,
            verticalInset: panelVerticalInset,
            companionSpacing: companionSpacing,
            contentWidth: panelContentWidth
        )
        let hostingView = NSHostingView(rootView: wrapperView)
        hostingView.frame = NSRect(
            x: 0,
            y: 0,
            width: panelSize.width,
            height: panelSize.height
        )
        hostingView.autoresizingMask = [.width, .height]
        // 设置 NSHostingView 背景为透明，让 SwiftUI 视图自己绘制背景
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView
        logger.info("Hosting view attached")
        
        self.hostingView = hostingView
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
        
        companionDismissWorkItem?.cancel()
        companionDismissWorkItem = nil
        withAnimation(.easeInOut(duration: 0.24)) {
            presentationModel.displayState = visualState(for: state)
            presentationModel.preset = DS.recordingBar.currentPreset
            presentationModel.colorScheme = colorScheme
            presentationModel.companion = nil
        }
        logger.info("Recording bar state updated to \(state.rawValue, privacy: .public)")
    }
    
    func showCompanion(_ companion: RecordingBarCompanion, displayState: RecordingBarVisualState = .failed) {
        companionDismissWorkItem?.cancel()
        companionDismissWorkItem = nil
        guard isShowing, let presentationModel else {
            show(state: .idle)
            guard let presentationModel else { return }
            presentationModel.displayState = displayState
            presentationModel.companion = companion
            scheduleCompanionAutoDismissIfNeeded(companion)
            return
        }
        
        let appearanceMode = UserDefaults.standard.string(forKey: "settings.appearanceMode") ?? "system"
        presentationModel.colorScheme = resolvedColorScheme(for: appearanceMode)
        presentationModel.preset = DS.recordingBar.currentPreset
        
        withAnimation(.easeInOut(duration: 0.22)) {
            presentationModel.displayState = displayState
            presentationModel.companion = companion
        }
        scheduleCompanionAutoDismissIfNeeded(companion)
    }
    
    func dismissCompanion() {
        companionDismissWorkItem?.cancel()
        companionDismissWorkItem = nil
        guard let presentationModel else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            presentationModel.companion = nil
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.hide()
        }
    }
    
    func openAppSettings(tab: String? = nil) {
        NSApp.activate(ignoringOtherApps: true)
        SettingsWindowCoordinator.shared.open?(tab)
    }
    
    func openSystemSettingsPrivacyPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// 隐藏悬浮录音条
    func hide() {
        logger.info("hide() called. hasPanel=\(self.panel != nil, privacy: .public)")
        companionDismissWorkItem?.cancel()
        companionDismissWorkItem = nil
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
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
    
    private func visualState(for state: AppState) -> RecordingBarVisualState {
        switch state {
        case .idle:
            return .idle
        case .listening:
            return .listening
        case .thinking:
            return .thinking
        case .speaking:
            return .speaking
        }
    }
    
    private func scheduleCompanionAutoDismissIfNeeded(_ companion: RecordingBarCompanion) {
        guard let delay = companion.autoDismissAfter else { return }
        let workItem = DispatchWorkItem { [weak self] in
            self?.dismissCompanion()
        }
        companionDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
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

struct RecordingBarCompanionAction {
    enum Style {
        case primary
        case secondary
    }
    
    let title: String
    let style: Style
    let handler: () -> Void
}

struct RecordingBarCompanion {
    let title: String
    let message: String
    let primaryAction: RecordingBarCompanionAction
    let secondaryAction: RecordingBarCompanionAction?
    let autoDismissAfter: TimeInterval?
}

@MainActor
private final class RecordingBarPresentationModel: ObservableObject {
    @Published var displayState: RecordingBarVisualState
    @Published var preset: DS.recordingBar.Preset
    @Published var colorScheme: ColorScheme
    @Published var companion: RecordingBarCompanion?
    
    init(displayState: RecordingBarVisualState, preset: DS.recordingBar.Preset, colorScheme: ColorScheme) {
        self.displayState = displayState
        self.preset = preset
        self.colorScheme = colorScheme
        self.companion = nil
    }
}

/// 包装 RecordingBarView，确保背景正确渲染
private struct RecordingBarWrapper: View {
    @ObservedObject var model: RecordingBarPresentationModel
    let horizontalInset: CGFloat
    let verticalInset: CGFloat
    let companionSpacing: CGFloat
    let contentWidth: CGFloat
    
    var body: some View {
        VStack(alignment: .leading, spacing: companionSpacing) {
            RecordingBarView(
                state: model.displayState,
                preset: model.preset,
                colorScheme: model.colorScheme
            )
            
            if let companion = model.companion {
                RecordingBarCompanionCard(
                    companion: companion,
                    colorScheme: model.colorScheme,
                    width: contentWidth
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, horizontalInset)
        .padding(.vertical, verticalInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.clear)
    }
}

private struct RecordingBarCompanionCard: View {
    let companion: RecordingBarCompanion
    let colorScheme: ColorScheme
    let width: CGFloat
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(accentMarkColor)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(companion.title)
                        .font(DS.font.mono(size: 13, weight: .medium))
                        .tracking(0.12)
                        .foregroundStyle(titleColor)
                    
                    Text(companion.message)
                        .font(.system(size: 13, weight: .regular, design: .default))
                        .foregroundStyle(messageColor)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            HStack(spacing: 10) {
                CompanionActionButton(action: companion.primaryAction, colorScheme: colorScheme)
                
                if let secondaryAction = companion.secondaryAction {
                    CompanionActionButton(action: secondaryAction, colorScheme: colorScheme)
                }
                
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: width, alignment: .leading)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(cardBorder, lineWidth: 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: shadowColor, radius: 10, x: 0, y: 4)
    }
    
    private var cardBackground: Color {
        colorScheme == .dark ? DS.color.surface2Dark : DS.color.surface
    }
    
    private var cardBorder: Color {
        colorScheme == .dark ? DS.color.borderDark.opacity(0.7) : DS.color.borderSoft.opacity(0.95)
    }
    
    private var titleColor: Color {
        colorScheme == .dark ? DS.color.foregroundDark : DS.color.foreground
    }
    
    private var messageColor: Color {
        colorScheme == .dark ? DS.color.mutedDark : DS.color.muted
    }
    
    private var accentMarkColor: Color {
        colorScheme == .dark ? DS.color.dangerDark : DS.color.danger
    }
    
    private var shadowColor: Color {
        colorScheme == .dark ? .black.opacity(0.14) : .black.opacity(0.06)
    }
}

private struct CompanionActionButton: View {
    let action: RecordingBarCompanionAction
    let colorScheme: ColorScheme
    
    var body: some View {
        Button(action.title, action: action.handler)
            .buttonStyle(.plain)
            .font(DS.font.mono(size: 12, weight: .medium))
            .tracking(0.08)
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(backgroundColor)
            .overlay(
                Capsule()
                    .strokeBorder(borderColor, lineWidth: 0.8)
            )
            .clipShape(Capsule())
    }
    
    private var foregroundColor: Color {
        switch action.style {
        case .primary:
            return colorScheme == .dark ? DS.color.foregroundDark : .white
        case .secondary:
            return colorScheme == .dark ? DS.color.mutedDark : DS.color.soft
        }
    }
    
    private var backgroundColor: Color {
        switch action.style {
        case .primary:
            return colorScheme == .dark ? DS.color.accentDarkSoft : DS.color.accent
        case .secondary:
            return colorScheme == .dark ? DS.color.surface3Dark.opacity(0.92) : Color.white.opacity(0.82)
        }
    }
    
    private var borderColor: Color {
        switch action.style {
        case .primary:
            return colorScheme == .dark ? DS.color.accentDark.opacity(0.42) : DS.color.accent.opacity(0.24)
        case .secondary:
            return colorScheme == .dark ? DS.color.borderDark.opacity(0.85) : DS.color.border.opacity(0.32)
        }
    }
}
