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
private enum RecordingBarCompanionPlacement {
    case above
    case below
}

final class FloatingRecordingBar {
    
    static let shared = FloatingRecordingBar()
    
    private let logger = Logger(subsystem: "dev.yanfch.Tsutae", category: "FloatingRecordingBar")
    private let savedOriginXKey = "recordingBar.origin.x"
    private let savedOriginYKey = "recordingBar.origin.y"
    private var panel: NSPanel?
    private var hostingView: NSHostingView<RecordingBarWrapper>?
    private var presentationModel: RecordingBarPresentationModel?
    private var companionDismissWorkItem: DispatchWorkItem?
    private var showsReleaseToFinishHint = false
    private(set) var isShowing = false
    private var currentState: AppState = .idle
    
    private init() {}
    
    private let panelHorizontalInset: CGFloat = 12
    private let panelVerticalInset: CGFloat = 10
    private let companionSpacing: CGFloat = 10
    private let companionHeight: CGFloat = 142
    private let companionMinWidth: CGFloat = 384
    
    private var companionVerticalShift: CGFloat {
        companionSpacing + companionHeight
    }
    
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
        show(state: state, initialDisplayState: nil, companion: nil)
    }
    
    private func show(state: AppState, initialDisplayState: RecordingBarVisualState?, companion: RecordingBarCompanion?) {
        let showStartedAt = CFAbsoluteTimeGetCurrent()
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
            self.savePanelOrigin(self.persistedOrigin(from: panel.frame.origin))
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
        
        let initialPlacement: RecordingBarCompanionPlacement
        if companion != nil {
            initialPlacement = resolvedCompanionPlacement(for: panel.frame, currentPlacement: .below)
            if initialPlacement == .above {
                let adjustedOrigin = clampedPanelOriginKeepingBarVisible(
                    NSPoint(x: panel.frame.origin.x, y: panel.frame.origin.y + companionVerticalShift),
                    placement: .above,
                    preferredScreen: panel.screen
                )
                panel.setFrameOrigin(adjustedOrigin)
            }
        } else {
            initialPlacement = .below
        }
        
        let presentationModel = RecordingBarPresentationModel(
            displayState: initialDisplayState ?? visualState(for: state),
            preset: DS.recordingBar.currentPreset,
            colorScheme: colorScheme,
            companionPlacement: initialPlacement,
            showsReleaseHint: showsReleaseToFinishHint
        )
        self.presentationModel = presentationModel
        
        let wrapperView = RecordingBarWrapper(
            model: presentationModel,
            horizontalInset: panelHorizontalInset,
            verticalInset: panelVerticalInset,
            companionSpacing: companionSpacing,
            companionVerticalShift: companionVerticalShift,
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
        
        if let companion {
            presentationModel.companion = companion
        }
        
        self.hostingView = hostingView
        self.panel = panel
        self.isShowing = true
        
        panel.alphaValue = 0
        panel.contentView?.layer?.setAffineTransform(CGAffineTransform(scaleX: 0.975, y: 0.975))
        DispatchQueue.main.async {
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().alphaValue = 1
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.contentView?.animator().layer?.setAffineTransform(.identity)
            }
            self.logger.info("Panel ordered front without activating app")
            PerformanceLog.record(
                category: "FloatingRecordingBar",
                message: "Recording panel ordered front. elapsed_ms=\(Self.formatElapsedMs(since: showStartedAt))"
            )
        }
        
        logger.info("show() completed")
        PerformanceLog.record(
            category: "FloatingRecordingBar",
            message: "Recording panel show completed. elapsed_ms=\(Self.formatElapsedMs(since: showStartedAt))"
        )
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
        restoreBarOnlyPositionIfNeeded()
        withAnimation(.easeInOut(duration: 0.24)) {
            presentationModel.displayState = visualState(for: state)
            presentationModel.preset = DS.recordingBar.currentPreset
            presentationModel.colorScheme = colorScheme
            presentationModel.showsReleaseHint = showsReleaseToFinishHint
            presentationModel.companion = nil
        }
        logger.info("Recording bar state updated to \(state.rawValue, privacy: .public)")
    }

    func showCompletion(copied: Bool = false) {
        currentState = .idle
        showsReleaseToFinishHint = false
        let displayState: RecordingBarVisualState = copied ? .copied : .idle

        guard isShowing else {
            show(state: .idle, initialDisplayState: displayState, companion: nil)
            return
        }

        guard let presentationModel else {
            logger.error("Failed to show recording completion because presentation model is missing")
            return
        }

        let appearanceMode = UserDefaults.standard.string(forKey: "settings.appearanceMode") ?? "system"
        companionDismissWorkItem?.cancel()
        companionDismissWorkItem = nil
        restoreBarOnlyPositionIfNeeded()
        withAnimation(.easeInOut(duration: 0.18)) {
            presentationModel.displayState = displayState
            presentationModel.preset = DS.recordingBar.currentPreset
            presentationModel.colorScheme = resolvedColorScheme(for: appearanceMode)
            presentationModel.showsReleaseHint = false
            presentationModel.companion = nil
        }
        logger.info("Recording bar completion shown. copied=\(copied, privacy: .public)")
    }
    
    func setReleaseToFinishHintVisible(_ isVisible: Bool) {
        showsReleaseToFinishHint = isVisible
        guard isShowing, let presentationModel else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            presentationModel.showsReleaseHint = isVisible
        }
    }
    
    func showCompanion(_ companion: RecordingBarCompanion, displayState: RecordingBarVisualState = .failed) {
        companionDismissWorkItem?.cancel()
        companionDismissWorkItem = nil
        guard isShowing, let presentationModel else {
            show(state: .idle, initialDisplayState: displayState, companion: companion)
            scheduleCompanionAutoDismissIfNeeded(companion)
            return
        }
        
        let appearanceMode = UserDefaults.standard.string(forKey: "settings.appearanceMode") ?? "system"
        presentationModel.colorScheme = resolvedColorScheme(for: appearanceMode)
        presentationModel.preset = DS.recordingBar.currentPreset
        
        applyBestCompanionPlacement()
        withAnimation(.easeInOut(duration: 0.22)) {
            presentationModel.displayState = displayState
            presentationModel.showsReleaseHint = showsReleaseToFinishHint
            presentationModel.companion = companion
        }
        scheduleCompanionAutoDismissIfNeeded(companion)
    }
    
    func dismissCompanion() {
        companionDismissWorkItem?.cancel()
        companionDismissWorkItem = nil
        guard presentationModel != nil else { return }
        hide(animated: true)
    }

    func clearCompanion(displayState: RecordingBarVisualState? = nil) {
        companionDismissWorkItem?.cancel()
        companionDismissWorkItem = nil
        guard isShowing, let presentationModel else { return }
        restoreBarOnlyPositionIfNeeded()
        withAnimation(.easeInOut(duration: 0.18)) {
            if let displayState {
                presentationModel.displayState = displayState
            }
            presentationModel.showsReleaseHint = showsReleaseToFinishHint
            presentationModel.companion = nil
        }
    }
    
    func openAppSettings(tab: String? = nil, focus: String? = nil) {
        if tab == "permissions" {
            if let focus, focus.isEmpty == false {
                UserDefaults.standard.set(focus, forKey: "settings.permissions.focus")
            } else {
                UserDefaults.standard.removeObject(forKey: "settings.permissions.focus")
            }
        }
        SettingsWindowCoordinator.shared.openSettings(tab: tab)
    }
    
    func openSystemSettingsPrivacyPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// 隐藏悬浮录音条
    func hide(animated: Bool = false) {
        logger.info("hide() called. hasPanel=\(self.panel != nil, privacy: .public)")
        companionDismissWorkItem?.cancel()
        companionDismissWorkItem = nil
        
        guard animated, let panel else {
            teardownPanel()
            logger.info("hide() completed")
            return
        }
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.contentView?.animator().layer?.setAffineTransform(CGAffineTransform(scaleX: 0.975, y: 0.975))
        } completionHandler: {
            self.teardownPanel()
            self.logger.info("hide() completed")
        }
    }
    
    /// 切换显示/隐藏
    func toggle() {
        logger.info("toggle() called. isShowing=\(self.isShowing, privacy: .public)")
        if isShowing {
            hide(animated: true)
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
    
    private func applyBestCompanionPlacement() {
        guard let panel, let presentationModel else { return }
        let placement = resolvedCompanionPlacement(for: panel.frame, currentPlacement: presentationModel.companionPlacement)
        guard placement != presentationModel.companionPlacement else { return }
        var origin = panel.frame.origin
        origin.y += placement == .above ? companionVerticalShift : -companionVerticalShift
        origin = clampedPanelOriginKeepingBarVisible(origin, placement: placement, preferredScreen: panel.screen)
        panel.setFrameOrigin(origin)
        presentationModel.companionPlacement = placement
    }
    
    private func restoreBarOnlyPositionIfNeeded() {
        guard let panel, let presentationModel, presentationModel.companionPlacement == .above else { return }
        let origin = clampedPanelOriginKeepingBarVisible(
            NSPoint(x: panel.frame.origin.x, y: panel.frame.origin.y - companionVerticalShift),
            placement: .below,
            preferredScreen: panel.screen
        )
        panel.setFrameOrigin(origin)
        presentationModel.companionPlacement = .below
    }
    
    private func resolvedCompanionPlacement(for panelFrame: NSRect, currentPlacement: RecordingBarCompanionPlacement) -> RecordingBarCompanionPlacement {
        let visibleFrame = (panel?.screen ?? screenForPresentation())?.visibleFrame ?? .zero
        let barFrame = barFrame(for: panelFrame, placement: currentPlacement)
        let requiredSpace = companionVerticalShift + panelVerticalInset
        let spaceBelow = barFrame.minY - visibleFrame.minY
        let spaceAbove = visibleFrame.maxY - barFrame.maxY
        
        if spaceBelow >= requiredSpace {
            return .below
        }
        if spaceAbove >= requiredSpace {
            return .above
        }
        return spaceAbove > spaceBelow ? .above : .below
    }
    
    private func barFrame(for panelFrame: NSRect, placement: RecordingBarCompanionPlacement) -> NSRect {
        let barOriginY: CGFloat
        switch placement {
        case .below:
            barOriginY = panelFrame.maxY - panelVerticalInset - layout.height
        case .above:
            barOriginY = panelFrame.maxY - panelVerticalInset - companionVerticalShift - layout.height
        }
        return NSRect(
            x: panelFrame.minX + panelHorizontalInset,
            y: barOriginY,
            width: layout.width,
            height: layout.height
        )
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
        let barFrame = barFrame(for: frame, placement: .below)
        guard let screen = NSScreen.screens.max(by: { $0.visibleFrame.intersection(barFrame).area < $1.visibleFrame.intersection(barFrame).area }) else {
            return nil
        }
        guard screen.visibleFrame.intersects(barFrame) else {
            return nil
        }
        return clampedPanelOriginKeepingBarVisible(origin, placement: .below, preferredScreen: screen)
    }
    
    private func persistedOrigin(from panelOrigin: NSPoint) -> NSPoint {
        guard let presentationModel, presentationModel.companionPlacement == .above else {
            return panelOrigin
        }
        return NSPoint(x: panelOrigin.x, y: panelOrigin.y - companionVerticalShift)
    }
    
    private func clampedPanelOriginKeepingBarVisible(
        _ origin: NSPoint,
        placement: RecordingBarCompanionPlacement,
        preferredScreen: NSScreen?
    ) -> NSPoint {
        let frame = NSRect(origin: origin, size: panelSize)
        let barFrame = barFrame(for: frame, placement: placement)
        let screen = preferredScreen
            ?? NSScreen.screens.first(where: { $0.visibleFrame.intersects(barFrame) })
            ?? screenForPresentation()
        let visibleFrame = screen?.visibleFrame ?? .zero
        let minX = visibleFrame.minX + panelHorizontalInset
        let maxX = max(minX, visibleFrame.maxX - panelHorizontalInset - layout.width)
        let minY = visibleFrame.minY + panelVerticalInset
        let maxY = max(minY, visibleFrame.maxY - panelVerticalInset - layout.height)
        let clampedBarOrigin = NSPoint(
            x: min(max(barFrame.minX, minX), maxX),
            y: min(max(barFrame.minY, minY), maxY)
        )
        let deltaX = clampedBarOrigin.x - barFrame.minX
        let deltaY = clampedBarOrigin.y - barFrame.minY
        return NSPoint(x: origin.x + deltaX, y: origin.y + deltaY)
    }
    
    private func savePanelOrigin(_ origin: NSPoint) {
        UserDefaults.standard.set(origin.x, forKey: savedOriginXKey)
        UserDefaults.standard.set(origin.y, forKey: savedOriginYKey)
        logger.info("Panel origin saved=(\(origin.x, privacy: .public), \(origin.y, privacy: .public))")
    }
    
    private func teardownPanel() {
        panel?.orderOut(nil)
        panel?.alphaValue = 1
        panel?.contentView?.layer?.setAffineTransform(.identity)
        panel = nil
        hostingView = nil
        presentationModel = nil
        showsReleaseToFinishHint = false
        isShowing = false
        currentState = .idle
    }

    private static func formatElapsedMs(since startedAt: CFAbsoluteTime) -> String {
        String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000.0)
    }
}

private extension NSRect {
    var area: CGFloat {
        width * height
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
    enum Tone {
        case info
        case warning
        case danger
    }
    
    let title: String
    let message: String
    let tone: Tone
    let primaryAction: RecordingBarCompanionAction?
    let secondaryAction: RecordingBarCompanionAction?
    let autoDismissAfter: TimeInterval?
}

@MainActor
private final class RecordingBarPresentationModel: ObservableObject {
    @Published var displayState: RecordingBarVisualState
    @Published var preset: DS.recordingBar.Preset
    @Published var colorScheme: ColorScheme
    @Published var companionPlacement: RecordingBarCompanionPlacement
    @Published var companion: RecordingBarCompanion?
    @Published var showsReleaseHint: Bool
    
    init(
        displayState: RecordingBarVisualState,
        preset: DS.recordingBar.Preset,
        colorScheme: ColorScheme,
        companionPlacement: RecordingBarCompanionPlacement,
        showsReleaseHint: Bool
    ) {
        self.displayState = displayState
        self.preset = preset
        self.colorScheme = colorScheme
        self.companionPlacement = companionPlacement
        self.companion = nil
        self.showsReleaseHint = showsReleaseHint
    }
}

/// 包装 RecordingBarView，确保背景正确渲染
private struct RecordingBarWrapper: View {
    @ObservedObject var model: RecordingBarPresentationModel
    let horizontalInset: CGFloat
    let verticalInset: CGFloat
    let companionSpacing: CGFloat
    let companionVerticalShift: CGFloat
    let contentWidth: CGFloat
    
    private var layout: DS.recordingBar.Layout {
        DS.recordingBar.layout(for: model.preset)
    }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            if let companion = model.companion, model.companionPlacement == .above {
                RecordingBarCompanionCard(
                    companion: companion,
                    colorScheme: model.colorScheme,
                    width: contentWidth,
                    height: companionReservedHeight
                )
                .offset(x: 0, y: 0)
                .transition(companionTransition(for: .above))
            }
            
            RecordingBarView(
                state: model.displayState,
                preset: model.preset,
                colorScheme: model.colorScheme,
                showsReleaseHint: model.showsReleaseHint
            )
            .offset(x: 0, y: barOffsetY)
            
            if let companion = model.companion, model.companionPlacement == .below {
                RecordingBarCompanionCard(
                    companion: companion,
                    colorScheme: model.colorScheme,
                    width: contentWidth,
                    height: companionReservedHeight
                )
                .offset(x: 0, y: companionBelowOffsetY)
                .transition(companionTransition(for: .below))
            }
        }
        .frame(width: contentWidth, height: contentHeight, alignment: .topLeading)
        .padding(.horizontal, horizontalInset)
        .padding(.vertical, verticalInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.clear)
    }
    
    private var companionReservedHeight: CGFloat {
        companionVerticalShift - companionSpacing
    }
    
    private var contentHeight: CGFloat {
        layout.height + companionSpacing + companionReservedHeight
    }
    
    private var barOffsetY: CGFloat {
        model.companionPlacement == .above ? companionVerticalShift : 0
    }
    
    private var companionBelowOffsetY: CGFloat {
        layout.height + companionSpacing
    }
    
    private func companionTransition(for placement: RecordingBarCompanionPlacement) -> AnyTransition {
        let offsetY: CGFloat = placement == .above ? -10 : 10
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: offsetY)),
            removal: .opacity
        )
    }
}

private struct RecordingBarCompanionCard: View {
    let companion: RecordingBarCompanion
    let colorScheme: ColorScheme
    let width: CGFloat
    let height: CGFloat
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(accentMarkColor.opacity(colorScheme == .dark ? 0.2 : 0.12))
                    Image(systemName: iconName)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(accentMarkColor)
                }
                .frame(width: 22, height: 22)
                .padding(.top, 1)
                
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
            
            if companion.primaryAction != nil || companion.secondaryAction != nil {
                HStack(spacing: 10) {
                    if let primaryAction = companion.primaryAction {
                        CompanionActionButton(action: primaryAction, colorScheme: colorScheme)
                    }
                    
                    if let secondaryAction = companion.secondaryAction {
                        CompanionActionButton(action: secondaryAction, colorScheme: colorScheme)
                    }
                    
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: width, height: height, alignment: .leading)
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
        switch companion.tone {
        case .info:
            return colorScheme == .dark ? DS.color.accentDark : DS.color.accent
        case .warning:
            return colorScheme == .dark ? DS.color.warningDark : DS.color.warning
        case .danger:
            return colorScheme == .dark ? DS.color.dangerDark : DS.color.danger
        }
    }

    private var iconName: String {
        switch companion.tone {
        case .info:
            return "info"
        case .warning:
            return "exclamationmark"
        case .danger:
            return "xmark"
        }
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
