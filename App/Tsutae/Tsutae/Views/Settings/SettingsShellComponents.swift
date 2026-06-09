import AppKit
import SwiftUI
import TsutaeCore

// MARK: - Sidebar

struct SettingsSidebar: View {
    @Binding var selectedTab: SettingsTab
    let selectionAnimation: Namespace.ID
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
                .frame(height: SettingsTokens.Padding.sidebarHeaderTop)
            
            VStack(alignment: .leading, spacing: SettingsTokens.Spacing.sidebarBlock) {
                SettingsSidebarBrand()
                
                SettingsSidebarSection {
                    ForEach(SettingsTab.primaryTabs) { tab in
                        SidebarItem(
                            tab: tab,
                            isSelected: selectedTab == tab,
                            selectionAnimation: selectionAnimation
                        ) {
                            selectedTab = tab
                        }
                    }
                }
                
                SettingsSidebarAdvancedRow(selectedTab: $selectedTab)
            }
            .padding(.horizontal, SettingsTokens.Padding.sidebarHorizontal)
            .padding(.top, SettingsTokens.Padding.sidebarTop)
            
            Spacer()
        }
        .background(sidebarBackground)
    }
    
    private var sidebarBackground: some View {
        Group {
            if colorScheme == .dark {
                DS.color.backgroundDark.opacity(0.76)
            } else {
                Color.white.opacity(0.38)
                    .overlay(.ultraThinMaterial)
            }
        }
    }
}

private struct SettingsSidebarBrand: View {
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Text("Tsutae")
            .font(.system(size: 17, weight: .semibold, design: .default))
            .foregroundStyle(colorScheme == .dark ? DS.color.foregroundDark.opacity(0.9) : DS.color.foreground)
            .padding(.horizontal, 8)
            .frame(height: 24, alignment: .leading)
            .padding(.bottom, 4)
    }
}

private struct SettingsSidebarSection<Content: View>: View {
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(spacing: 7) {
            content
        }
    }
}

private struct SettingsSidebarAdvancedRow: View {
    @Binding var selectedTab: SettingsTab
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(L10n.Settings.sidebarAdvanced)
                .font(DS.font.mono(size: 11, weight: .medium))
                .tracking(0.3)
                .foregroundStyle(colorScheme == .dark ? DS.color.foregroundDark.opacity(0.74) : DS.color.muted)
                .padding(.leading, 10)
            
            FlexibleTagRow(items: SettingsTab.secondaryTabs, selectedTab: $selectedTab)
        }
    }
}

private struct SidebarItem: View {
    let tab: SettingsTab
    let isSelected: Bool
    let selectionAnimation: Namespace.ID
    let action: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 18)
                
                Text(tab.title)
                    .font(.system(size: 14, weight: .medium))
                
                Spacer(minLength: 0)
                
                Circle()
                    .fill(isSelected ? Color.white.opacity(0.85) : DS.color.accent.opacity(0.35))
                    .frame(width: 6, height: 6)
            }
            .foregroundStyle(isSelected ? Color.white : foregroundColor)
            .padding(.horizontal, 12)
            .frame(height: SettingsTokens.Size.sidebarItemHeight)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(backgroundColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder(borderColor, lineWidth: isSelected ? 0 : 1)
                        )
                    
                    if isSelected {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(DS.color.accent)
                            .matchedGeometryEffect(id: "settings-sidebar-selection", in: selectionAnimation)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.18, extraBounce: 0), value: isSelected)
    }
    
    private var foregroundColor: Color {
        colorScheme == .dark ? DS.color.foregroundDark : DS.color.foreground
    }
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.04) : Color.white.opacity(0.58)
    }
    
    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
    }
}

private struct FlexibleTagRow: View {
    let items: [SettingsTab]
    @Binding var selectedTab: SettingsTab
    
    var body: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(items) { tab in
                Button(tab.title) {
                    selectedTab = tab
                }
                .buttonStyle(SecondaryChipButtonStyle(isSelected: selectedTab == tab))
            }
        }
    }
}

// MARK: - General Settings

private struct SecondaryChipButtonStyle: ButtonStyle {
    let isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: isSelected ? .medium : .regular))
            .foregroundStyle(foreground)
            .padding(.horizontal, 9)
            .frame(height: SettingsTokens.Size.secondaryChipHeight)
            .background(
                Capsule()
                    .fill(background(configuration: configuration))
                    .overlay(
                        Capsule()
                            .strokeBorder(border, lineWidth: 1)
                    )
            )
    }
    
    private var foreground: Color {
        if colorScheme == .dark {
            return isSelected ? Color.white.opacity(0.98) : DS.color.foregroundDark.opacity(0.9)
        }
        return isSelected ? Color.white : DS.color.muted
    }
    
    private func background(configuration: Configuration) -> Color {
        if colorScheme == .dark {
            if isSelected {
                return DS.color.accent.opacity(configuration.isPressed ? 0.74 : 0.88)
            }
            return DS.color.surface2Dark.opacity(configuration.isPressed ? 0.98 : 0.9)
        }
        return isSelected ? DS.color.accent.opacity(configuration.isPressed ? 0.8 : 0.92) : Color.white.opacity(configuration.isPressed ? 0.78 : 0.58)
    }
    
    private var border: Color {
        if colorScheme == .dark {
            return isSelected ? DS.color.accent.opacity(0.96) : DS.color.borderDarkSoft.opacity(0.42)
        }
        return isSelected ? DS.color.accent.opacity(0.9) : Color.black.opacity(0.04)
    }
}

struct SettingsPageChrome: View {
    private struct STTSummary {
        let modeTitle: String
        let fallbackTitle: String
        let remoteTitle: String
        let fallbackTone: ServerStatusCapsule.Tone
        let remoteTone: ServerStatusCapsule.Tone
        
        static func load() -> STTSummary {
            make(from: (try? ConfigLoader.load()) ?? .default)
        }
        
        static func make(from config: Config) -> STTSummary {
            let modeTitle = config.stt.mode == .remoteFirst ? L10n.Settings.sttModeRemoteFirst : L10n.Settings.sttModeLocalFirst
            let fallbackEnabled = config.stt.fallbackEngine != nil
            let fallbackTitle = fallbackEnabled ? L10n.Settings.sttFallbackOn : L10n.Settings.sttNoFallback
            let fallbackTone: ServerStatusCapsule.Tone = fallbackEnabled ? .active : .neutral
            let remoteReady = config.stt.remote.enabled && (config.stt.remote.baseURL?.isEmpty == false) && (config.stt.remote.model?.isEmpty == false)
            let remoteTitle: String
            let remoteTone: ServerStatusCapsule.Tone
            if config.stt.remote.enabled == false {
                remoteTitle = L10n.Settings.sttRemoteOff
                remoteTone = .neutral
            } else if remoteReady {
                remoteTitle = L10n.Settings.sttRemoteReady
                remoteTone = .active
            } else {
                remoteTitle = L10n.Settings.sttNeedsSetup
                remoteTone = .neutral
            }
            return STTSummary(
                modeTitle: modeTitle,
                fallbackTitle: fallbackTitle,
                remoteTitle: remoteTitle,
                fallbackTone: fallbackTone,
                remoteTone: remoteTone
            )
        }
    }
    
    let tab: SettingsTab
    @Environment(\.colorScheme) private var colorScheme
    @State private var sttSummary = STTSummary.load()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(tab.title)
                        .font(.system(size: 27, weight: .semibold, design: .default))
                        .foregroundStyle(colorScheme == .dark ? DS.color.foregroundDark : DS.color.foreground)
                    Text(tab.subtitle)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(colorScheme == .dark ? DS.color.mutedDark : DS.color.muted)
                }
                
                Spacer(minLength: 20)
                
                HStack(spacing: 8) {
                    summaryPills
                }
                .padding(.top, 2)
            }
            
            Divider()
                .overlay(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
        }
        .padding(.horizontal, 30)
        .padding(.top, 22)
        .padding(.bottom, 16)
        .background(settingsChromeBackground)
        .onAppear {
            refreshSTTSummary()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tsutaeConfigDidChange)) { notification in
            if let config = notification.userInfo?["config"] as? Config {
                sttSummary = STTSummary.make(from: config)
            } else {
                refreshSTTSummary()
            }
        }
    }
    
    @ViewBuilder
    private var summaryPills: some View {
        switch tab {
        case .stt:
            summaryCapsule(title: sttSummary.modeTitle, tone: .active)
            summaryCapsule(title: sttSummary.fallbackTitle, tone: sttSummary.fallbackTone)
            summaryCapsule(title: sttSummary.remoteTitle, tone: sttSummary.remoteTone)
        case .tts:
            summaryCapsule(title: L10n.Settings.chromePlayback, tone: .soft)
            summaryCapsule(title: L10n.Settings.chromeCloudOptional, tone: .neutral)
        case .server:
            summaryCapsule(title: L10n.Settings.chromeSTTTTS, tone: .soft)
            summaryCapsule(title: L10n.Settings.chromeHooksPlanned, tone: .active)
        case .permissions:
            summaryCapsule(title: L10n.Settings.statusReview, tone: .soft)
        default:
            summaryCapsule(title: tab.statusTitle, tone: .soft)
        }
    }
    
    private func summaryCapsule(title: String, tone: ServerStatusCapsule.Tone) -> some View {
        ServerStatusCapsule(title: title, tone: tone)
            .opacity(summaryCapsuleOpacity(for: tone))
    }
    
    private func summaryCapsuleOpacity(for tone: ServerStatusCapsule.Tone) -> Double {
        switch tone {
        case .active, .success, .warning:
            return 1
        case .soft:
            return colorScheme == .dark ? 0.82 : 0.9
        case .neutral:
            return colorScheme == .dark ? 0.66 : 0.82
        }
    }
    
    private var settingsChromeBackground: Color {
        colorScheme == .dark ? DS.color.surfaceDark : DS.color.settingsBgLight
    }
    
    private func refreshSTTSummary() {
        sttSummary = STTSummary.load()
    }
}


// MARK: - Window Host

struct SettingsWindowHost: NSViewRepresentable {
    let content: AnyView
    @Binding var titlebarCompensation: CGFloat
    let colorScheme: ColorScheme
    let appearanceOverride: ColorScheme?
    
    func makeNSView(context: Context) -> SafeAreaIgnoringHostingView<AnyView> {
        let view = SafeAreaIgnoringHostingView(rootView: content)
        
        DispatchQueue.main.async {
            configureWindow(for: view)
        }
        
        return view
    }
    
    func updateNSView(_ nsView: SafeAreaIgnoringHostingView<AnyView>, context: Context) {
        nsView.rootView = content
        
        DispatchQueue.main.async {
            configureWindow(for: nsView)
        }
    }
    
    private func configureWindow(for view: NSView) {
        guard let window = view.window else { return }
        
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbar = nil
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = nsWindowBackgroundColor
        window.appearance = nsAppearance
        window.hasShadow = colorScheme != .dark
        
        if #available(macOS 15.0, *) {
            window.toolbarStyle = .unifiedCompact
            window.titlebarSeparatorStyle = .none
        }
        
        view.wantsLayer = true
        view.layer?.backgroundColor = nsWindowBackgroundColor.cgColor
        view.layer?.cornerRadius = 24
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        
        if let contentView = window.contentView {
            contentView.appearance = nsAppearance
            contentView.wantsLayer = true
            contentView.layer?.backgroundColor = nsWindowBackgroundColor.cgColor
            contentView.layer?.cornerRadius = 24
            contentView.layer?.cornerCurve = .continuous
            contentView.layer?.masksToBounds = true
            
            if let frameView = contentView.superview {
                frameView.wantsLayer = true
                frameView.layer?.backgroundColor = nsWindowBackgroundColor.cgColor
                frameView.layer?.cornerRadius = 24
                frameView.layer?.cornerCurve = .continuous
                frameView.layer?.masksToBounds = true
                
                if let rootFrameView = frameView.superview {
                    rootFrameView.wantsLayer = true
                    rootFrameView.layer?.backgroundColor = nsWindowBackgroundColor.cgColor
                    rootFrameView.layer?.cornerRadius = 24
                    rootFrameView.layer?.cornerCurve = .continuous
                    rootFrameView.layer?.masksToBounds = true
                }
            }
        }
        
        if let titlebarView = window.standardWindowButton(.closeButton)?.superview {
            titlebarView.wantsLayer = true
            titlebarView.layer?.backgroundColor = nsWindowBackgroundColor.cgColor
            titlebarView.layer?.cornerRadius = 24
            titlebarView.layer?.cornerCurve = .continuous
            titlebarView.layer?.masksToBounds = true
            
            if let titlebarContainer = titlebarView.superview {
                titlebarContainer.wantsLayer = true
                titlebarContainer.layer?.backgroundColor = nsWindowBackgroundColor.cgColor
                titlebarContainer.layer?.cornerRadius = 24
                titlebarContainer.layer?.cornerCurve = .continuous
                titlebarContainer.layer?.masksToBounds = true
            }
        }
        
        let titlebarHeight = window.frame.height - window.contentLayoutRect.height
        let compensation = -(titlebarHeight + 10)
        if abs(titlebarCompensation - compensation) > 0.5 {
            titlebarCompensation = compensation
        }
        
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.level = .normal
        window.alphaValue = 1
        window.invalidateShadow()
    }
    
    private var nsWindowBackgroundColor: NSColor {
        switch colorScheme {
        case .dark:
            return NSColor(calibratedRed: 0x1A / 255, green: 0x23 / 255, blue: 0x20 / 255, alpha: 1)
        case .light:
            return NSColor(calibratedRed: 0xF2 / 255, green: 0xF1 / 255, blue: 0xDF / 255, alpha: 1)
        @unknown default:
            return NSColor.windowBackgroundColor
        }
    }
    
    private var nsAppearance: NSAppearance? {
        switch appearanceOverride {
        case .dark:
            return NSAppearance(named: .darkAqua)
        case .light:
            return NSAppearance(named: .aqua)
        case nil:
            return nil
        @unknown default:
            return nil
        }
    }
}

final class SafeAreaIgnoringHostingView<Content: View>: NSHostingView<Content> {
    private lazy var passthroughSafeAreaLayoutGuide = NSLayoutGuide()
    
    required init(rootView: Content) {
        super.init(rootView: rootView)
        addLayoutGuide(passthroughSafeAreaLayoutGuide)
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: passthroughSafeAreaLayoutGuide.leadingAnchor),
            topAnchor.constraint(equalTo: passthroughSafeAreaLayoutGuide.topAnchor),
            trailingAnchor.constraint(equalTo: passthroughSafeAreaLayoutGuide.trailingAnchor),
            bottomAnchor.constraint(equalTo: passthroughSafeAreaLayoutGuide.bottomAnchor)
        ])
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
    }
    
    override var safeAreaRect: NSRect { frame }
    
    override var safeAreaInsets: NSEdgeInsets {
        NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }
    
    override var safeAreaLayoutGuide: NSLayoutGuide {
        passthroughSafeAreaLayoutGuide
    }
    
    override var additionalSafeAreaInsets: NSEdgeInsets {
        get { NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0) }
        set {}
    }
}
