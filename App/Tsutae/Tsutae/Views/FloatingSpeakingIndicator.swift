import SwiftUI
import Combine
import TsutaeCore
import OSLog

private enum SpeakingCompanionPlacement {
    case above
    case below
}

final class FloatingSpeakingIndicator {
    static let shared = FloatingSpeakingIndicator()

    private let logger = Logger(subsystem: "dev.yanfch.Tsutae", category: "FloatingSpeakingIndicator")
    private let savedBarOriginXKey = "speakingIndicator.bar.origin.x"
    private let savedBarOriginYKey = "speakingIndicator.bar.origin.y"
    private var panel: NSPanel?
    private var hostingView: NSHostingView<SpeakingIndicatorWrapper>?
    private var presentationModel: SpeakingIndicatorPresentationModel?
    private var observer: NSObjectProtocol?
    private var companionDismissWorkItem: DispatchWorkItem?

    private let horizontalInset: CGFloat = 12
    private let verticalInset: CGFloat = 10
    private let companionSpacing: CGFloat = 10
    private let companionHeight: CGFloat = 76
    private let companionWidth: CGFloat = 356
    private let standardChipWidth: CGFloat = 248
    private let minimalChipWidth: CGFloat = 136
    private let chipHeight: CGFloat = DS.recordingBar.layout(for: .standard).height

    private var companionVerticalShift: CGFloat {
        companionSpacing + companionHeight
    }

    private init() {}

    func startObserving() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .tsutaeTTSPlaybackDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.syncWithPlaybackManager()
        }
        syncWithPlaybackManager()
    }

    private func syncWithPlaybackManager() {
        let snapshot = TTSPlaybackManager.shared.snapshot()
        if snapshot.state == .idle {
            hide(animated: true)
        } else {
            showOrUpdate(snapshot: snapshot)
        }
    }

    private func showOrUpdate(snapshot: TTSPlaybackSnapshot) {
        let metrics = panelMetrics(for: snapshot)
        let appearanceMode = UserDefaults.standard.string(forKey: "settings.appearanceMode") ?? "system"
        let colorScheme = resolvedColorScheme(for: appearanceMode)

        if let presentationModel, let panel {
            let barOrigin = currentBarOrigin(
                from: panel.frame,
                placement: presentationModel.companionPlacement,
                metrics: panelMetrics(for: presentationModel.snapshot)
            )
            presentationModel.snapshot = snapshot
            presentationModel.colorScheme = colorScheme
            presentationModel.reservesCompanionSpace = metrics.showsCompanionRegion
            presentationModel.contentWidth = metrics.contentWidth
            panel.setContentSize(metrics.panelSize)
            let origin = clampedPanelOrigin(forBarOrigin: barOrigin, placement: presentationModel.companionPlacement, metrics: metrics, preferredScreen: panel.screen)
            panel.setFrameOrigin(origin)
            presentationModel.isCompanionVisible = false
            return
        }

        let panel = DraggableSpeakingPanel(
            contentRect: NSRect(origin: .zero, size: metrics.panelSize),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.onDragEnded = { [weak self, weak panel] in
            guard let self, let panel, let presentationModel = self.presentationModel else { return }
            let metrics = self.panelMetrics(for: presentationModel.snapshot)
            let origin = self.clampedPanelOrigin(
                forBarOrigin: self.currentBarOrigin(from: panel.frame, placement: presentationModel.companionPlacement, metrics: metrics),
                placement: presentationModel.companionPlacement,
                metrics: metrics,
                preferredScreen: panel.screen
            )
            panel.setFrameOrigin(origin)
            self.saveBarOrigin(self.currentBarOrigin(from: panel.frame, placement: presentationModel.companionPlacement, metrics: metrics))
        }
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.ignoresMouseEvents = false

        if appearanceMode == "light" {
            panel.appearance = NSAppearance(named: .aqua)
        } else if appearanceMode == "dark" {
            panel.appearance = NSAppearance(named: .darkAqua)
        } else {
            panel.appearance = nil
        }

        let initialBarOrigin = savedBarOrigin(metrics: metrics) ?? defaultBarOrigin(metrics: metrics)
        let initialPlacement = bestCompanionPlacement(forBarOrigin: initialBarOrigin, metrics: metrics, preferredScreen: screenForPresentation())
        panel.setFrameOrigin(clampedPanelOrigin(forBarOrigin: initialBarOrigin, placement: initialPlacement, metrics: metrics, preferredScreen: screenForPresentation()))

        let presentationModel = SpeakingIndicatorPresentationModel(
            snapshot: snapshot,
            colorScheme: colorScheme,
            reservesCompanionSpace: metrics.showsCompanionRegion,
            contentWidth: metrics.contentWidth,
            companionPlacement: initialPlacement
        )
        presentationModel.onHoverChanged = { [weak self] isHovering in
            self?.handleHoverChanged(isHovering)
        }
        self.presentationModel = presentationModel

        let wrapper = SpeakingIndicatorWrapper(
            model: presentationModel,
            horizontalInset: horizontalInset,
            verticalInset: verticalInset,
            companionSpacing: companionSpacing,
            companionHeight: companionHeight
        )
        let hostingView = NSHostingView(rootView: wrapper)
        hostingView.frame = NSRect(origin: .zero, size: metrics.panelSize)
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView

        self.panel = panel
        self.hostingView = hostingView

        panel.alphaValue = 0
        panel.contentView?.layer?.setAffineTransform(CGAffineTransform(scaleX: 0.975, y: 0.975))
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 1
            panel.contentView?.animator().layer?.setAffineTransform(.identity)
        }

        presentationModel.isCompanionVisible = false
    }

    private func handleHoverChanged(_ isHovering: Bool) {
        guard let presentationModel else { return }
        companionDismissWorkItem?.cancel()
        guard presentationModel.snapshot.presentationStyle == .standard,
              presentationModel.snapshot.state == .speaking else {
            presentationModel.isCompanionVisible = false
            return
        }

        if isHovering {
            applyBestCompanionPlacement()
            presentationModel.isCompanionVisible = true
        } else {
            let workItem = DispatchWorkItem { [weak self] in
                self?.presentationModel?.isCompanionVisible = false
            }
            companionDismissWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: workItem)
        }
    }

    private func applyBestCompanionPlacement() {
        guard let panel, let presentationModel else { return }
        let metrics = panelMetrics(for: presentationModel.snapshot)
        let barOrigin = currentBarOrigin(from: panel.frame, placement: presentationModel.companionPlacement, metrics: metrics)
        let placement = bestCompanionPlacement(forBarOrigin: barOrigin, metrics: metrics, preferredScreen: panel.screen)
        guard placement != presentationModel.companionPlacement else { return }
        panel.setFrameOrigin(clampedPanelOrigin(forBarOrigin: barOrigin, placement: placement, metrics: metrics, preferredScreen: panel.screen))
        presentationModel.companionPlacement = placement
    }

    private func hide(animated: Bool) {
        guard let panel else { return }
        companionDismissWorkItem?.cancel()
        companionDismissWorkItem = nil

        let cleanup = { [weak self] in
            self?.panel?.orderOut(nil)
            self?.panel = nil
            self?.hostingView = nil
            self?.presentationModel = nil
        }

        guard animated else {
            cleanup()
            return
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0
            panel.contentView?.animator().layer?.setAffineTransform(CGAffineTransform(scaleX: 0.975, y: 0.975))
        }) {
            cleanup()
        }
    }

    private func panelMetrics(for snapshot: TTSPlaybackSnapshot) -> SpeakingPanelMetrics {
        let chipWidth = snapshot.presentationStyle == .minimal ? minimalChipWidth : standardChipWidth
        let showsCompanionRegion = snapshot.presentationStyle == .standard
        let contentWidth = showsCompanionRegion ? max(chipWidth, companionWidth) : chipWidth
        let contentHeight = showsCompanionRegion ? chipHeight + companionVerticalShift : chipHeight
        let panelSize = NSSize(
            width: contentWidth + horizontalInset * 2,
            height: contentHeight + verticalInset * 2
        )
        return SpeakingPanelMetrics(
            chipWidth: chipWidth,
            chipHeight: chipHeight,
            contentWidth: contentWidth,
            showsCompanionRegion: showsCompanionRegion,
            panelSize: panelSize
        )
    }

    private func currentBarOrigin(from panelFrame: NSRect, placement: SpeakingCompanionPlacement, metrics: SpeakingPanelMetrics) -> NSPoint {
        let frame = barFrame(for: panelFrame, placement: placement, metrics: metrics)
        return frame.origin
    }

    private func barFrame(for panelFrame: NSRect, placement: SpeakingCompanionPlacement, metrics: SpeakingPanelMetrics) -> NSRect {
        let barOriginY: CGFloat
        if metrics.showsCompanionRegion {
            switch placement {
            case .above:
                barOriginY = panelFrame.minY + verticalInset
            case .below:
                barOriginY = panelFrame.minY + verticalInset + companionVerticalShift
            }
        } else {
            barOriginY = panelFrame.minY + verticalInset
        }
        return NSRect(
            x: panelFrame.minX + horizontalInset,
            y: barOriginY,
            width: metrics.chipWidth,
            height: metrics.chipHeight
        )
    }

    private func clampedPanelOrigin(
        forBarOrigin barOrigin: NSPoint,
        placement: SpeakingCompanionPlacement,
        metrics: SpeakingPanelMetrics,
        preferredScreen: NSScreen?
    ) -> NSPoint {
        let screen = preferredScreen
            ?? NSScreen.screens.first(where: { $0.visibleFrame.contains(barOrigin) })
            ?? screenForPresentation()
        let visibleFrame = screen?.visibleFrame ?? .zero
        let clampedBarX = min(
            max(barOrigin.x, visibleFrame.minX + horizontalInset),
            max(visibleFrame.minX + horizontalInset, visibleFrame.maxX - horizontalInset - metrics.contentWidth)
        )
        let clampedBarY = min(
            max(barOrigin.y, visibleFrame.minY + verticalInset),
            max(visibleFrame.minY + verticalInset, visibleFrame.maxY - verticalInset - metrics.chipHeight)
        )
        let resolvedBarOrigin = NSPoint(x: clampedBarX, y: clampedBarY)
        return panelOrigin(forBarOrigin: resolvedBarOrigin, placement: placement, metrics: metrics)
    }

    private func panelOrigin(forBarOrigin barOrigin: NSPoint, placement: SpeakingCompanionPlacement, metrics: SpeakingPanelMetrics) -> NSPoint {
        let panelY: CGFloat
        if metrics.showsCompanionRegion {
            switch placement {
            case .above:
                panelY = barOrigin.y - verticalInset
            case .below:
                panelY = barOrigin.y - verticalInset - companionVerticalShift
            }
        } else {
            panelY = barOrigin.y - verticalInset
        }
        return NSPoint(x: barOrigin.x - horizontalInset, y: panelY)
    }

    private func bestCompanionPlacement(forBarOrigin barOrigin: NSPoint, metrics: SpeakingPanelMetrics, preferredScreen: NSScreen?) -> SpeakingCompanionPlacement {
        guard metrics.showsCompanionRegion else { return .above }
        let screen = preferredScreen
            ?? NSScreen.screens.first(where: { $0.visibleFrame.contains(barOrigin) })
            ?? screenForPresentation()
        let visibleFrame = screen?.visibleFrame ?? .zero
        let spaceAbove = visibleFrame.maxY - (barOrigin.y + metrics.chipHeight)
        let spaceBelow = barOrigin.y - visibleFrame.minY
        let required = companionVerticalShift + verticalInset
        if spaceAbove >= required { return .above }
        if spaceBelow >= required { return .below }
        return spaceAbove >= spaceBelow ? .above : .below
    }

    private func defaultBarOrigin(metrics: SpeakingPanelMetrics) -> NSPoint {
        guard let screen = screenForPresentation() else { return .zero }
        let visibleFrame = screen.visibleFrame
        return NSPoint(
            x: visibleFrame.midX - metrics.chipWidth / 2,
            y: visibleFrame.minY + 18
        )
    }

    private func savedBarOrigin(metrics: SpeakingPanelMetrics) -> NSPoint? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: savedBarOriginXKey) != nil,
              defaults.object(forKey: savedBarOriginYKey) != nil else {
            return nil
        }
        let origin = NSPoint(
            x: defaults.double(forKey: savedBarOriginXKey),
            y: defaults.double(forKey: savedBarOriginYKey)
        )
        let placement = bestCompanionPlacement(forBarOrigin: origin, metrics: metrics, preferredScreen: nil)
        let panelOrigin = clampedPanelOrigin(forBarOrigin: origin, placement: placement, metrics: metrics, preferredScreen: nil)
        return currentBarOrigin(from: NSRect(origin: panelOrigin, size: metrics.panelSize), placement: placement, metrics: metrics)
    }

    private func saveBarOrigin(_ origin: NSPoint) {
        UserDefaults.standard.set(origin.x, forKey: savedBarOriginXKey)
        UserDefaults.standard.set(origin.y, forKey: savedBarOriginYKey)
        logger.info("Speaking indicator bar origin saved=(\(origin.x, privacy: .public), \(origin.y, privacy: .public))")
    }

    private func screenForPresentation() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
            ?? NSApp.keyWindow?.screen
            ?? NSScreen.main
    }

    private func resolvedColorScheme(for mode: String) -> ColorScheme {
        switch mode {
        case "light": return .light
        case "dark": return .dark
        default:
            if let appearance = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]), appearance == .darkAqua {
                return .dark
            }
            return .light
        }
    }
}

private struct SpeakingPanelMetrics {
    let chipWidth: CGFloat
    let chipHeight: CGFloat
    let contentWidth: CGFloat
    let showsCompanionRegion: Bool
    let panelSize: NSSize
}

private final class DraggableSpeakingPanel: NSPanel {
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
        guard let dragStartLocation, let dragStartOrigin else { return }
        let currentLocation = NSEvent.mouseLocation
        let deltaX = currentLocation.x - dragStartLocation.x
        let deltaY = currentLocation.y - dragStartLocation.y
        setFrameOrigin(NSPoint(x: dragStartOrigin.x + deltaX, y: dragStartOrigin.y + deltaY))
    }

    override func mouseUp(with event: NSEvent) {
        dragStartLocation = nil
        dragStartOrigin = nil
        onDragEnded?()
    }
}

@MainActor
private final class SpeakingIndicatorPresentationModel: ObservableObject {
    @Published var snapshot: TTSPlaybackSnapshot
    @Published var colorScheme: ColorScheme
    @Published var reservesCompanionSpace: Bool
    @Published var contentWidth: CGFloat
    @Published var companionPlacement: SpeakingCompanionPlacement
    @Published var isCompanionVisible = false
    var onHoverChanged: ((Bool) -> Void)?

    init(snapshot: TTSPlaybackSnapshot, colorScheme: ColorScheme, reservesCompanionSpace: Bool, contentWidth: CGFloat, companionPlacement: SpeakingCompanionPlacement) {
        self.snapshot = snapshot
        self.colorScheme = colorScheme
        self.reservesCompanionSpace = reservesCompanionSpace
        self.contentWidth = contentWidth
        self.companionPlacement = companionPlacement
    }
}

private struct SpeakingIndicatorWrapper: View {
    @ObservedObject var model: SpeakingIndicatorPresentationModel
    let horizontalInset: CGFloat
    let verticalInset: CGFloat
    let companionSpacing: CGFloat
    let companionHeight: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            if model.reservesCompanionSpace && model.companionPlacement == .above {
                companionSlot
                    .offset(y: 0)
            }

            SpeakingChipView(snapshot: model.snapshot, colorScheme: model.colorScheme) {
                TTSPlaybackManager.shared.stop()
            }
            .offset(y: barOffsetY)
            .onHover { model.onHoverChanged?($0) }

            if model.reservesCompanionSpace && model.companionPlacement == .below {
                companionSlot
                    .offset(y: companionBelowOffsetY)
            }
        }
        .frame(width: model.contentWidth, height: contentHeight, alignment: .topLeading)
        .padding(.horizontal, horizontalInset)
        .padding(.vertical, verticalInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: model.isCompanionVisible)
    }

    @ViewBuilder
    private var companionSlot: some View {
        if model.isCompanionVisible, let summary = model.snapshot.text {
            SpeakingCompanionCard(
                source: model.snapshot.source ?? "Tsutae",
                summary: summary,
                startedAt: model.snapshot.startedAt,
                colorScheme: model.colorScheme,
                width: model.contentWidth,
                height: companionHeight
            )
            .transition(.move(edge: model.companionPlacement == .above ? .bottom : .top).combined(with: .opacity))
        } else {
            Color.clear
                .frame(width: model.contentWidth, height: companionHeight)
        }
    }

    private var contentHeight: CGFloat {
        model.reservesCompanionSpace ? companionHeight + companionSpacing + DS.recordingBar.layout(for: .standard).height : DS.recordingBar.layout(for: .standard).height
    }

    private var barOffsetY: CGFloat {
        guard model.reservesCompanionSpace else { return 0 }
        return model.companionPlacement == .above ? companionHeight + companionSpacing : 0
    }

    private var companionBelowOffsetY: CGFloat {
        DS.recordingBar.layout(for: .standard).height + companionSpacing
    }
}

private struct SpeakingChipView: View {
    let snapshot: TTSPlaybackSnapshot
    let colorScheme: ColorScheme
    let stopAction: () -> Void

    private var isDarkMode: Bool { colorScheme == .dark }
    private var layout: SpeakingChipLayout { SpeakingChipLayout(style: snapshot.presentationStyle) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.08)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: layout.contentSpacing) {
                leadingCluster(phase: phase)
                    .frame(width: layout.leadingWidth, alignment: .leading)

                if layout.showsSource {
                    sourceSlot
                        .frame(width: layout.sourceWidth, alignment: .center)
                }

                actionSlot
                    .frame(width: layout.actionWidth)
            }
            .padding(.leading, layout.leadingPadding)
            .padding(.trailing, layout.trailingPadding)
            .frame(width: layout.width, height: layout.height)
            .background(capsuleBackground)
            .overlay(capsuleBorder)
            .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowYOffset)
        }
    }

    private func leadingCluster(phase: Double) -> some View {
        HStack(spacing: layout.leadingClusterSpacing) {
            Image(systemName: "speaker.wave.2")
                .font(.system(size: layout.iconSize, weight: .medium))
                .foregroundStyle(accentColor)
                .symbolRenderingMode(.hierarchical)

            SpeakingBars(phase: phase, color: accentColor, layout: layout)
        }
    }

    private var sourceSlot: some View {
        HStack(spacing: 6) {
            Text(formattedSource(snapshot.source ?? "Tsutae"))
                .font(DS.font.mono(size: layout.sourceFontSize, weight: .regular))
                .tracking(0.02)
                .foregroundStyle(foregroundColor)
                .lineLimit(1)
                .truncationMode(.tail)

            if snapshot.queueLength > 0 {
                Text("+\(snapshot.queueLength)")
                    .font(DS.font.mono(size: 10, weight: .medium))
                    .foregroundStyle(isDarkMode ? DS.color.accentDark : DS.color.accent)
                    .padding(.horizontal, 5)
                    .frame(height: 18)
                    .background(
                        Capsule()
                            .fill(isDarkMode ? DS.color.accentDark.opacity(0.14) : DS.color.accent.opacity(0.1))
                            .overlay(
                                Capsule()
                                    .strokeBorder(isDarkMode ? DS.color.accentDark.opacity(0.24) : DS.color.accent.opacity(0.18), lineWidth: 1)
                            )
                    )
            }
        }
    }

    private var actionSlot: some View {
        stopButton
    }

    private var stopButton: some View {
        Button(action: stopAction) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(keycapBackgroundColor)
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(keycapBorderColor, lineWidth: 1)
                Image(systemName: "stop.fill")
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(keycapForegroundColor.opacity(0.86))
            }
            .frame(width: layout.keycapWidth, height: layout.keycapHeight)
        }
        .buttonStyle(.plain)
    }

    private var capsuleBackground: some View {
        RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
            .fill(isDarkMode ? DS.color.surfaceDark : DS.color.surface)
    }

    private var capsuleBorder: some View {
        RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: capsuleBorderColors,
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: isDarkMode ? 0.6 : 0.5
            )
    }

    private var capsuleBorderColors: [Color] {
        if isDarkMode {
            return [
                Color.white.opacity(0.12),
                DS.color.borderDarkSoft.opacity(0.16),
                Color.black.opacity(0.14)
            ]
        }
        return [
            Color.white.opacity(0.08),
            Color.white.opacity(0.04),
            Color.white.opacity(0.06)
        ]
    }

    private var foregroundColor: Color {
        isDarkMode ? DS.color.foregroundDark : DS.color.foreground
    }

    private var accentColor: Color {
        isDarkMode ? DS.color.accentDark : DS.color.accent
    }

    private var keycapForegroundColor: Color {
        isDarkMode ? DS.color.foregroundDark.opacity(0.92) : DS.color.foreground.opacity(0.88)
    }

    private var keycapBackgroundColor: Color {
        isDarkMode ? DS.color.surface2Dark : Color.white.opacity(0.55)
    }

    private var keycapBorderColor: Color {
        isDarkMode ? DS.color.borderDark.opacity(0.9) : DS.color.border.opacity(0.38)
    }

    private var shadowColor: Color {
        isDarkMode ? .black.opacity(0.18) : DS.color.accent.opacity(0.04)
    }

    private var shadowRadius: CGFloat {
        isDarkMode ? 5 : 4
    }

    private var shadowYOffset: CGFloat {
        isDarkMode ? 2 : 1
    }
}

private struct SpeakingChipLayout {
    let height: CGFloat
    let width: CGFloat
    let cornerRadius: CGFloat
    let leadingPadding: CGFloat
    let trailingPadding: CGFloat
    let contentSpacing: CGFloat
    let leadingClusterSpacing: CGFloat
    let leadingWidth: CGFloat
    let showsSource: Bool
    let sourceWidth: CGFloat
    let sourceFontSize: CGFloat
    let actionWidth: CGFloat
    let keycapWidth: CGFloat
    let keycapHeight: CGFloat
    let dividerHeight: CGFloat
    let iconSize: CGFloat
    let barHeights: [CGFloat]
    let barWidth: CGFloat
    let barSpacing: CGFloat

    init(style: Config.TTSPresentationStyle) {
        switch style {
        case .standard:
            let base = DS.recordingBar.layout(for: .standard)
            height = base.height
            width = 248
            cornerRadius = base.cornerRadius
            leadingPadding = base.leadingPadding
            trailingPadding = base.trailingPadding
            contentSpacing = base.contentSpacing
            leadingClusterSpacing = 7
            leadingWidth = 64
            showsSource = true
            sourceWidth = 96
            sourceFontSize = 11.5
            actionWidth = base.keycapWidth
            keycapWidth = base.keycapWidth
            keycapHeight = 26
            dividerHeight = 19
            iconSize = 15
            barHeights = [8, 18, 11]
            barWidth = 5
            barSpacing = 6
        case .minimal:
            let base = DS.recordingBar.layout(for: .minimal)
            height = base.height
            width = 136
            cornerRadius = base.cornerRadius
            leadingPadding = base.leadingPadding
            trailingPadding = 12
            contentSpacing = 8
            leadingClusterSpacing = 7
            leadingWidth = 54
            showsSource = false
            sourceWidth = 0
            sourceFontSize = 13
            actionWidth = 34
            keycapWidth = 34
            keycapHeight = 22
            dividerHeight = 16
            iconSize = 13
            barHeights = [6, 12, 8]
            barWidth = 4
            barSpacing = 4
        }
    }
}

private struct SpeakingBars: View {
    let phase: Double
    let color: Color
    let layout: SpeakingChipLayout

    var body: some View {
        HStack(spacing: layout.barSpacing) {
            ForEach(Array(layout.barHeights.enumerated()), id: \.offset) { index, baseHeight in
                RoundedRectangle(cornerRadius: layout.barWidth / 2, style: .continuous)
                    .fill(barColor(for: index))
                    .frame(width: layout.barWidth, height: baseHeight)
                    .scaleEffect(y: 0.82 + CGFloat((sin(phase * 4.1 + Double(index) * 0.8) + 1) * 0.16))
            }
        }
        .frame(height: 20)
    }

    private func barColor(for index: Int) -> Color {
        switch index {
        case 0:
            return color.opacity(0.36)
        case 1:
            return color
        case layout.barHeights.count - 1:
            return color.opacity(0.82)
        default:
            return color.opacity(0.68)
        }
    }
}

private struct SpeakingCompanionCard: View {
    let source: String
    let summary: String
    let startedAt: Date?
    let colorScheme: ColorScheme
    let width: CGFloat
    let height: CGFloat

    private var isDarkMode: Bool { colorScheme == .dark }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isDarkMode ? DS.color.surface3Dark.opacity(0.92) : Color.white.opacity(0.52))
                .frame(width: 38, height: 38)
                .overlay(
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(isDarkMode ? DS.color.accentDark : DS.color.accent)
                )

            VStack(alignment: .leading, spacing: 0) {
                Text(summary)
                    .font(.system(size: 12.25, weight: .regular))
                    .lineLimit(2)
                    .foregroundStyle(isDarkMode ? DS.color.mutedDark : DS.color.muted)
            }

            Spacer(minLength: 10)

            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                Text(elapsedText(now: context.date))
                    .font(DS.font.mono(size: 11, weight: .regular))
                    .foregroundStyle(isDarkMode ? DS.color.mutedDark : DS.color.muted)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: width, height: height, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isDarkMode ? DS.color.surface2Dark : DS.color.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(isDarkMode ? DS.color.borderDark.opacity(0.7) : DS.color.borderSoft.opacity(0.95), lineWidth: 0.8)
                )
                .shadow(color: isDarkMode ? .black.opacity(0.14) : .black.opacity(0.06), radius: 10, x: 0, y: 4)
        )
    }

    private func elapsedText(now: Date) -> String {
        guard let startedAt else { return "0:00" }
        let seconds = max(0, Int(now.timeIntervalSince(startedAt)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private func formattedSource(_ source: String) -> String {
    guard let first = source.first else { return source }
    return String(first).uppercased() + source.dropFirst()
}
