import AppKit
import SwiftUI
import TsutaeCore

struct SettingsDropdownOption: Identifiable {
    let id: String
    let title: String
    var isDisabled = false
}

enum SettingsDropdownTone {
    case active
    case soft
}

struct SettingsDropdown: View {
    let selection: Binding<String>
    let options: [SettingsDropdownOption]
    var tone: SettingsDropdownTone = .soft
    var width: CGFloat? = nil
    var menuWidth: CGFloat? = nil
    var maxMenuHeight: CGFloat? = nil
    @State private var isPresented = false
    @State private var hoveredOptionID: String?
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 10) {
                Text(selectedTitle)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: isPresented ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .font(DS.font.mono(size: 12, weight: tone == .active ? .medium : .regular))
            .foregroundStyle(colorScheme == .dark ? DS.color.foregroundDark : DS.color.foreground)
            .padding(.horizontal, SettingsTokens.Padding.sidebarHorizontal)
            .frame(width: width, height: SettingsTokens.Size.controlHeight, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(backgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(borderColor, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            Group {
                if let maxMenuHeight {
                    ScrollView {
                        optionsList
                    }
                    .frame(maxHeight: maxMenuHeight)
                } else {
                    optionsList
                }
            }
            .padding(8)
            .frame(width: menuWidth ?? max(width ?? 200, SettingsTokens.Width.modelFilterDropdown))
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(colorScheme == .dark ? DS.color.surface2Dark : Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.08) : DS.color.borderSoft.opacity(0.5), lineWidth: 1)
                    )
            )
            .padding(8)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var optionsList: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(options) { option in
                Button {
                    guard option.isDisabled == false else { return }
                    selection.wrappedValue = option.id
                    isPresented = false
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: selection.wrappedValue == option.id ? "checkmark" : "circle")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(selection.wrappedValue == option.id ? DS.color.accent : .secondary)
                        Text(option.title)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                    }
                    .font(.system(size: 13, weight: selection.wrappedValue == option.id ? .semibold : .regular))
                    .foregroundStyle(option.isDisabled ? .secondary.opacity(0.65) : (colorScheme == .dark ? DS.color.foregroundDark : DS.color.foreground))
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                    .contentShape(Rectangle())
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill((selection.wrappedValue == option.id || hoveredOptionID == option.id) ? DS.color.accent.opacity(0.12) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .disabled(option.isDisabled)
                .opacity(option.isDisabled ? 0.45 : 1)
                .onHover { isHovering in
                    hoveredOptionID = isHovering ? option.id : nil
                }
            }
        }
    }
    
    private var selectedTitle: String {
        options.first(where: { $0.id == selection.wrappedValue })?.title ?? options.first?.title ?? L10n.Common.select
    }
    
    private var backgroundColor: Color {
        switch tone {
        case .active:
            return colorScheme == .dark ? DS.color.accentDark.opacity(0.22) : DS.color.accent.opacity(0.12)
        case .soft:
            return colorScheme == .dark ? DS.color.surface2Dark.opacity(0.92) : Color.white.opacity(0.88)
        }
    }
    
    private var borderColor: Color {
        switch tone {
        case .active:
            return colorScheme == .dark ? DS.color.accentDark.opacity(0.4) : DS.color.accent.opacity(0.28)
        case .soft:
            return colorScheme == .dark ? DS.color.borderDarkSoft.opacity(0.45) : DS.color.borderSoft.opacity(0.52)
        }
    }
}

struct SettingsSearchField: View {
    @Binding var text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(L10n.Settings.sttSearchModelsPlaceholder, text: $text)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, SettingsTokens.Padding.sidebarHorizontal)
        .frame(width: SettingsTokens.Size.searchFieldWidth, height: SettingsTokens.Size.controlHeight)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(colorScheme == .dark ? DS.color.surface2Dark.opacity(0.92) : Color.white.opacity(0.88))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(colorScheme == .dark ? DS.color.borderDarkSoft.opacity(0.45) : DS.color.borderSoft.opacity(0.52), lineWidth: 1)
                )
        )
    }
}

struct SettingsDangerButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(colorScheme == .dark ? DS.color.warningDark : DS.color.warning)
            .padding(.horizontal, SettingsTokens.Padding.buttonHorizontal)
            .frame(height: SettingsTokens.Size.buttonHeight)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill((colorScheme == .dark ? DS.color.warningDark : DS.color.warning).opacity(configuration.isPressed ? 0.18 : 0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder((colorScheme == .dark ? DS.color.warningDark : DS.color.warning).opacity(0.28), lineWidth: 1)
            )
    }
}

struct SettingsDangerIconButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(colorScheme == .dark ? DS.color.warningDark : DS.color.warning)
            .frame(width: SettingsTokens.Size.iconButton, height: SettingsTokens.Size.iconButton)
            .background(
                Circle()
                    .fill((colorScheme == .dark ? DS.color.warningDark : DS.color.warning).opacity(configuration.isPressed ? 0.18 : 0.1))
            )
            .overlay(
                Circle()
                    .strokeBorder((colorScheme == .dark ? DS.color.warningDark : DS.color.warning).opacity(0.24), lineWidth: 1)
            )
    }
}

struct SettingsChipSelector: View {
    let selection: Binding<String>
    let options: [(id: String, title: String)]
    @State private var optionFrames: [String: CGRect] = [:]
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            Capsule()
                .fill(colorScheme == .dark ? DS.color.surface2Dark.opacity(0.9) : Color.white.opacity(0.72))
                .overlay(
                    Capsule()
                        .strokeBorder(idleBorder, lineWidth: 1)
                )
            
            if let frame = optionFrames[selection.wrappedValue] {
                Capsule()
                    .fill(colorScheme == .dark ? DS.color.accent.opacity(0.9) : DS.color.accent.opacity(0.92))
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
                    .overlay(
                        Capsule()
                            .strokeBorder(selectedBorder, lineWidth: 1)
                            .frame(width: frame.width, height: frame.height)
                            .offset(x: frame.minX, y: frame.minY)
                    )
                    .shadow(color: colorScheme == .dark ? DS.color.accent.opacity(0.18) : DS.color.accent.opacity(0.14), radius: 8, x: 0, y: 1)
                    .animation(.spring(response: 0.34, dampingFraction: 0.84, blendDuration: 0.12), value: selection.wrappedValue)
            }
            
            HStack(spacing: 4) {
                ForEach(options, id: \.id) { option in
                    let isSelected = selection.wrappedValue == option.id
                    Button {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.84, blendDuration: 0.12)) {
                            selection.wrappedValue = option.id
                        }
                    } label: {
                        Text(option.title)
                            .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                            .foregroundStyle(isSelected ? selectedForeground : idleForeground)
                            .padding(.horizontal, 11)
                            .frame(height: SettingsTokens.Size.secondaryChipHeight + 1)
                            .background(
                                GeometryReader { proxy in
                                    Color.clear
                                        .preference(
                                            key: SettingsChipSelectorFramePreferenceKey.self,
                                            value: [option.id: proxy.frame(in: .named("settings-chip-selector-space"))]
                                        )
                                }
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
        }
        .fixedSize(horizontal: true, vertical: true)
        .coordinateSpace(name: "settings-chip-selector-space")
        .onPreferenceChange(SettingsChipSelectorFramePreferenceKey.self) { frames in
            optionFrames = frames
        }
    }
    
    private var selectedForeground: Color {
        colorScheme == .dark ? Color.white.opacity(0.98) : Color.white
    }
    
    private var idleForeground: Color {
        colorScheme == .dark ? DS.color.foregroundDark.opacity(0.9) : DS.color.muted
    }
    
    private var selectedBorder: Color {
        colorScheme == .dark ? DS.color.accent.opacity(0.96) : DS.color.accent.opacity(0.9)
    }
    
    private var idleBorder: Color {
        colorScheme == .dark ? DS.color.borderDarkSoft.opacity(0.42) : Color.black.opacity(0.04)
    }
}

struct SettingsChipSelectorFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct STTInlineDownloadProgress: View {
    let progress: Double
    @State private var displayedProgress: Double = 0

    var body: some View {
        HStack(spacing: 10) {
            STTModelDownloadProgressBar(progress: displayedProgress)
                .frame(height: 8)
            STTAnimatedDownloadProgressLabel(progress: displayedProgress)
                .font(DS.font.mono(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .trailing)
        }
        .onAppear {
            displayedProgress = clamped(progress)
        }
        .onChange(of: progress) { _, newValue in
            let target = clamped(newValue)
            let delta = abs(target - displayedProgress)
            let duration = min(max(0.22, delta * 2.8), 1.8)
            withAnimation(.linear(duration: duration)) {
                displayedProgress = target
            }
        }
    }

    private func clamped(_ value: Double) -> Double {
        max(0, min(value, 1))
    }
}

private struct STTAnimatedDownloadProgressLabel: View, Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Text(progressLabel)
    }

    private var progressLabel: String {
        let clamped = max(0, min(progress, 1))
        if clamped == 0 {
            return "0%"
        }
        if clamped < 0.01 {
            return "<1%"
        }
        if clamped < 0.1 {
            return String(format: "%.1f%%", clamped * 100)
        }
        return "\(Int(clamped * 100))%"
    }
}

private struct STTModelDownloadProgressBar: View {
    let progress: Double
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            let clamped = max(0, min(progress, 1))
            let track = Capsule()

            ZStack(alignment: .leading) {
                track
                    .fill(colorScheme == .dark ? Color.white.opacity(0.08) : DS.color.surface3.opacity(0.7))

                if clamped <= 0 {
                    TimelineView(.animation) { context in
                        let segmentWidth = max(geometry.size.width * 0.34, 28)
                        let cycle = 1.05
                        let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle) / cycle
                        let travel = geometry.size.width + segmentWidth
                        let offset = -segmentWidth + travel * phase

                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        DS.color.accent.opacity(0.08),
                                        DS.color.accent.opacity(0.9),
                                        DS.color.accent.opacity(0.08),
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: segmentWidth)
                            .offset(x: offset)
                    }
                } else {
                    Capsule()
                        .fill(DS.color.accent)
                        .frame(width: max(geometry.size.height, geometry.size.width * clamped))
                }
            }
            .clipShape(track)
        }
    }
}

struct SettingsRecordingShortcutControl: View {
    let shortcutID: String
    let onChange: (String) -> Void

    @State private var rememberedKeyboardShortcutID: String

    init(shortcutID: String, onChange: @escaping (String) -> Void) {
        self.shortcutID = shortcutID
        self.onChange = onChange
        _rememberedKeyboardShortcutID = State(
            initialValue: RecordingShortcut.keyboardShortcutID(forShortcutID: shortcutID)
                ?? RecordingShortcut.defaultKeyboardShortcutID
        )
    }

    var body: some View {
        HStack(spacing: 10) {
            SettingsDropdown(
                selection: modeSelection,
                options: modeOptions,
                width: 150,
                menuWidth: 180
            )

            if currentMode == .keyboardShortcut {
                SettingsShortcutRecorderField(
                    shortcutID: rememberedKeyboardShortcutID,
                    onChange: { newShortcutID in
                        rememberedKeyboardShortcutID = newShortcutID
                        onChange(RecordingShortcut.id(mode: .keyboardShortcut, keyboardShortcutID: newShortcutID))
                    }
                )
            } else {
                SettingsDropdown(
                    selection: modifierSelection,
                    options: modifierOptions,
                    width: 150,
                    menuWidth: 180
                )
            }
        }
        .onAppear {
            syncRememberedKeyboardShortcut(from: shortcutID)
        }
        .onChange(of: shortcutID) { _, newValue in
            syncRememberedKeyboardShortcut(from: newValue)
        }
    }

    private var currentMode: RecordingShortcutMode {
        RecordingShortcut.mode(forShortcutID: shortcutID)
    }

    private var currentModifier: RecordingShortcutModifier {
        RecordingShortcut.modifier(forShortcutID: shortcutID) ?? RecordingShortcut.defaultModifier
    }

    private var modeSelection: Binding<String> {
        Binding(
            get: { currentMode.rawValue },
            set: { newValue in
                let newMode = RecordingShortcutMode(rawValue: newValue) ?? .keyboardShortcut
                onChange(
                    RecordingShortcut.id(
                        mode: newMode,
                        keyboardShortcutID: rememberedKeyboardShortcutID,
                        modifier: currentModifier
                    )
                )
            }
        )
    }

    private var modifierSelection: Binding<String> {
        Binding(
            get: { currentModifier.rawValue },
            set: { newValue in
                let modifier = RecordingShortcutModifier(rawValue: newValue) ?? RecordingShortcut.defaultModifier
                onChange(
                    RecordingShortcut.id(
                        mode: currentMode,
                        keyboardShortcutID: rememberedKeyboardShortcutID,
                        modifier: modifier
                    )
                )
            }
        )
    }

    private var modeOptions: [SettingsDropdownOption] {
        [
            SettingsDropdownOption(id: RecordingShortcutMode.keyboardShortcut.rawValue, title: L10n.Settings.recordingShortcutModeKeyboard),
            SettingsDropdownOption(id: RecordingShortcutMode.doubleTapModifier.rawValue, title: L10n.Settings.recordingShortcutModeDoubleTap),
            SettingsDropdownOption(id: RecordingShortcutMode.pressAndHoldModifier.rawValue, title: L10n.Settings.recordingShortcutModeHold),
        ]
    }

    private var modifierOptions: [SettingsDropdownOption] {
        RecordingShortcutModifier.allCases.map { modifier in
            SettingsDropdownOption(id: modifier.rawValue, title: "\(modifier.glyph) \(modifierTitle(for: modifier))")
        }
    }

    private func modifierTitle(for modifier: RecordingShortcutModifier) -> String {
        switch modifier {
        case .control: return L10n.Settings.recordingShortcutModifierControl
        case .option: return L10n.Settings.recordingShortcutModifierOption
        case .shift: return L10n.Settings.recordingShortcutModifierShift
        case .command: return L10n.Settings.recordingShortcutModifierCommand
        }
    }

    private func syncRememberedKeyboardShortcut(from id: String) {
        guard let keyboardShortcutID = RecordingShortcut.keyboardShortcutID(forShortcutID: id) else {
            return
        }
        rememberedKeyboardShortcutID = keyboardShortcutID
    }
}

struct SettingsShortcutRecorderField: View {
    let shortcutID: String
    let onChange: (String) -> Void
    
    @ObservedObject private var hotkeyManager = GlobalHotkeyManager.shared
    @State private var isRecording = false
    @State private var eventMonitor: Any?
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button {
            isRecording.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "keyboard")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isRecording ? DS.color.accent : .secondary)
                
                Group {
                    if isRecording {
                        Text(L10n.Settings.recordingShortcutPrompt)
                            .font(DS.font.mono(size: 12, weight: .medium))
                            .tracking(0.04)
                    } else {
                        Text(hotkeyManager.displayString(forShortcutID: shortcutID))
                            .font(.system(size: 13.25, weight: .regular, design: .rounded))
                            .tracking(0.01)
                            .foregroundStyle(colorScheme == .dark ? DS.color.foregroundDark.opacity(0.88) : DS.color.foreground.opacity(0.86))
                    }
                }
                .lineLimit(1)
                
                Spacer(minLength: 8)
                
                Text(isRecording ? L10n.Settings.recordingShortcutCancelHint : L10n.Settings.recordingShortcutRecordHint)
                    .font(DS.font.mono(size: 10.5, weight: .medium))
                    .foregroundStyle(isRecording ? DS.color.accent : .secondary)
            }
            .foregroundStyle(colorScheme == .dark ? DS.color.foregroundDark : DS.color.foreground)
            .padding(.horizontal, 13)
            .frame(width: SettingsTokens.Size.shortcutFieldWidth, height: SettingsTokens.Size.controlHeight, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(isRecording ? (colorScheme == .dark ? DS.color.accentDark.opacity(0.22) : DS.color.accent.opacity(0.12)) : (colorScheme == .dark ? DS.color.surface2Dark.opacity(0.92) : Color.white.opacity(0.88)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(isRecording ? (colorScheme == .dark ? DS.color.accentDark.opacity(0.48) : DS.color.accent.opacity(0.34)) : (colorScheme == .dark ? DS.color.borderDarkSoft.opacity(0.45) : DS.color.borderSoft.opacity(0.52)), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .onChange(of: isRecording) { _, newValue in
            if newValue {
                startRecordingShortcut()
            } else {
                stopRecordingShortcut()
            }
        }
        .onDisappear {
            stopRecordingShortcut()
        }
    }
    
    private func startRecordingShortcut() {
        stopRecordingShortcut()
        hotkeyManager.beginShortcutCapture()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                isRecording = false
                return nil
            }
            guard let shortcut = hotkeyManager.shortcutID(from: event) else {
                NSSound.beep()
                return nil
            }
            onChange(shortcut)
            isRecording = false
            return nil
        }
    }
    
    private func stopRecordingShortcut() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        hotkeyManager.endShortcutCapture()
    }
}
