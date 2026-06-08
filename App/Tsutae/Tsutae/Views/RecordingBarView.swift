import SwiftUI

enum RecordingBarVisualState {
    case idle
    case listening
    case waiting
    case thinking
    case speaking
    case warning
    case failed
}

/// 纸感录音胶囊 — 共用一套骨架，按 preset 切换标准 / 极简
struct RecordingBarView: View {
    
    let state: RecordingBarVisualState
    let preset: DS.recordingBar.Preset
    let colorScheme: ColorScheme
    
    private let phaseOffsets: [Double] = [0, 0.7, 1.2, 1.8, 2.4, 3.0, 3.6, 4.2, 4.8]
    
    @State private var completionPulse: CGFloat = 0
    
    private var layout: DS.recordingBar.Layout {
        DS.recordingBar.layout(for: preset)
    }
    
    init(
        state: RecordingBarVisualState,
        preset: DS.recordingBar.Preset = DS.recordingBar.defaultPreset,
        colorScheme: ColorScheme = .light
    ) {
        self.state = state
        self.preset = preset
        self.colorScheme = colorScheme
    }
    
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { context in
            let wavePhase = waveformPhase(for: context.date)
            let breathPhase = breathingPhase(for: context.date)
            
            HStack(spacing: layout.contentSpacing) {
                leadingCluster(wavePhase: wavePhase, breathPhase: breathPhase)
                
                if layout.showsStatusLabel {
                    statusLabelSlot
                }
                
                if layout.showsKeycap {
                    keycapSlot
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, layout.leadingPadding)
            .padding(.trailing, layout.trailingPadding)
            .padding(.vertical, layout.verticalPadding)
            .frame(width: layout.width, height: layout.height)
            .background(
                backgroundShape
                    .fill(backgroundColor)
                    .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowYOffset)
            )
            .overlay(
                backgroundShape
                    .strokeBorder(
                        LinearGradient(
                            colors: capsuleBorderColors,
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: capsuleBorderWidth
                    )
            )
        }
        .onChange(of: state) { _, newState in
            if newState == .idle {
                triggerCompletionPulse()
            }
        }
    }
    
    // MARK: - 布局片段
    
    private var backgroundShape: some InsettableShape {
        RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
    }
    
    private func leadingCluster(wavePhase: Double, breathPhase: Double) -> some View {
        HStack(spacing: layout.leadingClusterSpacing) {
            breathingDot(breathPhase: breathPhase)
            waveformView(wavePhase: wavePhase)
        }
    }
    
    // MARK: - 呼吸发光圆点
    
    private func breathingDot(breathPhase: Double) -> some View {
        ZStack {
            Circle()
                .fill(stateColor.opacity(isDarkMode ? 0.14 : 0.08))
                .frame(width: layout.dotGlowSize, height: layout.dotGlowSize)
                .scaleEffect(1.0 + sin(breathPhase) * 0.08 + completionPulse)
                .opacity(0.58 + sin(breathPhase) * 0.16)
            
            if preset == .minimal && state == .idle {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(successColor)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.88).combined(with: .opacity),
                        removal: .opacity
                    ))
            } else if preset == .minimal && (state == .warning || state == .failed) {
                Image(systemName: "exclamationmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(state == .warning ? warningColor : dangerColor)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.9).combined(with: .opacity),
                        removal: .opacity
                    ))
            } else {
                Circle()
                    .fill(stateColor)
                    .frame(width: layout.dotSize, height: layout.dotSize)
                    .transition(.opacity)
            }
        }
        .scaleEffect(1 + completionPulse * 0.45)
        .animation(.spring(response: 0.3, dampingFraction: 0.84), value: state)
    }
    
    private func waveformView(wavePhase: Double) -> some View {
        HStack(alignment: .center, spacing: layout.barSpacing) {
            ForEach(0..<layout.barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: layout.barCornerRadius, style: .continuous)
                    .fill(waveformColor)
                    .frame(width: layout.barWidth, height: layout.waveformHeights[index])
                    .scaleEffect(y: barScaleFactor(at: index, wavePhase: wavePhase))
                    .opacity(barOpacity(at: index, wavePhase: wavePhase))
                    .animation(.easeInOut(duration: 0.24), value: state)
            }
        }
        .frame(width: layout.waveformWidth, height: layout.waveformHeight, alignment: .leading)
    }
    
    // MARK: - 状态文字
    
    private var statusLabelSlot: some View {
        ZStack {
            Text(stateLabel)
                .font(statusFont)
                .italic()
                .tracking(statusTracking)
                .foregroundStyle(statusLabelColor)
                .lineLimit(1)
                .id(stateLabel)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(y: 3)),
                    removal: .opacity.combined(with: .offset(y: -3))
                ))
        }
        .frame(width: layout.statusWidth, alignment: .center)
        .animation(.easeInOut(duration: 0.24), value: stateLabel)
    }
    
    // MARK: - 热键提示
    
    private var keycapSlot: some View {
        ZStack {
            keycapView(text: keycapText)
                .id(keycapText)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.94).combined(with: .opacity),
                    removal: .opacity
                ))
        }
        .frame(width: layout.keycapWidth)
        .animation(.spring(response: 0.3, dampingFraction: 0.86), value: keycapText)
    }
    
    private func keycapView(text: String) -> some View {
        Text(text)
            .font(keycapFont)
            .tracking(keycapTracking)
            .foregroundStyle(keycapForegroundColor)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, layout.keycapHorizontalPadding)
            .padding(.vertical, layout.keycapVerticalPadding)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(keycapBackgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(keycapBorderColor, lineWidth: 1)
            )
            .animation(.easeInOut(duration: 0.22), value: state)
    }
    
    // MARK: - 计算属性
    
    private var stateLabel: String {
        switch state {
        case .idle: return "Done"
        case .listening: return "Listen"
        case .waiting: return "Wait"
        case .thinking: return "Think"
        case .speaking: return "Speak"
        case .warning: return "Review"
        case .failed: return "Failed"
        }
    }
    
    private var keycapText: String {
        switch state {
        case .idle: return "✓"
        case .listening: return "Esc"
        case .waiting: return "Esc"
        case .thinking: return "Esc"
        case .speaking: return "⌥R"
        case .warning: return "Esc"
        case .failed: return "Esc"
        }
    }
    
    private var statusFont: Font {
        DS.font.mono(size: layout.statusFontSize, weight: .regular)
    }
    
    private var keycapFont: Font {
        DS.font.mono(size: layout.keycapFontSize, weight: .medium)
    }
    
    private var statusTracking: CGFloat {
        0.32
    }
    
    private var keycapTracking: CGFloat {
        0.12
    }
    
    // MARK: - 颜色
    
    private var isDarkMode: Bool {
        colorScheme == .dark
    }
    
    private var accentColor: Color {
        isDarkMode ? DS.color.accentDark : DS.color.accent
    }
    
    private var successColor: Color {
        isDarkMode ? DS.color.successDark : DS.color.success
    }
    
    private var warningColor: Color {
        isDarkMode ? DS.color.warningDark : DS.color.warning
    }
    
    private var dangerColor: Color {
        isDarkMode ? DS.color.dangerDark : DS.color.danger
    }
    
    private var statusLabelColor: Color {
        isDarkMode ? DS.color.foregroundDark : DS.color.foreground
    }
    
    private var backgroundColor: Color {
        isDarkMode ? DS.color.surfaceDark : Color(red: 0xFF / 255, green: 0xFD / 255, blue: 0xF3 / 255)
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
    
    private var capsuleBorderWidth: CGFloat {
        isDarkMode ? 0.6 : 0.5
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
    
    private var stateColor: Color {
        switch state {
        case .idle:
            return preset == .standard ? accentColor : successColor
        case .listening:
            return accentColor
        case .waiting:
            return accentColor
        case .thinking:
            return accentColor
        case .speaking:
            return successColor
        case .warning:
            return warningColor
        case .failed:
            return dangerColor
        }
    }
    
    private var waveformColor: Color {
        switch state {
        case .idle, .listening, .waiting, .thinking:
            return accentColor
        case .speaking:
            return successColor
        case .warning:
            return warningColor
        case .failed:
            return dangerColor
        }
    }
    
    private var keycapForegroundColor: Color {
        if isDarkMode {
            switch state {
            case .idle:
                return successColor
            case .listening:
                return DS.color.mutedDark
            case .waiting:
                return accentColor
            case .thinking:
                return accentColor
            case .speaking:
                return successColor
            case .warning:
                return warningColor
            case .failed:
                return dangerColor
            }
        }
        
        switch state {
        case .idle:
            return DS.color.success
        case .listening:
            return DS.color.soft
        case .waiting:
            return DS.color.accent
        case .thinking:
            return DS.color.accent
        case .speaking:
            return DS.color.success
        case .warning:
            return DS.color.warning
        case .failed:
            return DS.color.danger
        }
    }
    
    private var keycapBackgroundColor: Color {
        if isDarkMode {
            switch state {
            case .idle:
                return successColor.opacity(0.14)
            case .listening:
                return DS.color.surface2Dark
            case .waiting:
                return DS.color.accentDarkSoft.opacity(0.24)
            case .thinking:
                return DS.color.accentDarkSoft.opacity(0.24)
            case .speaking:
                return successColor.opacity(0.14)
            case .warning:
                return warningColor.opacity(0.16)
            case .failed:
                return dangerColor.opacity(0.16)
            }
        }
        
        switch state {
        case .idle:
            return DS.color.success.opacity(0.1)
        case .listening:
            return Color.white.opacity(0.55)
        case .waiting:
            return DS.color.accent.opacity(0.08)
        case .thinking:
            return DS.color.accent.opacity(0.08)
        case .speaking:
            return DS.color.success.opacity(0.1)
        case .warning:
            return DS.color.warning.opacity(0.1)
        case .failed:
            return DS.color.danger.opacity(0.1)
        }
    }
    
    private var keycapBorderColor: Color {
        if isDarkMode {
            switch state {
            case .idle:
                return successColor.opacity(0.34)
            case .listening:
                return DS.color.borderDark.opacity(0.9)
            case .waiting:
                return accentColor.opacity(0.32)
            case .thinking:
                return accentColor.opacity(0.32)
            case .speaking:
                return successColor.opacity(0.34)
            case .warning:
                return warningColor.opacity(0.34)
            case .failed:
                return dangerColor.opacity(0.36)
            }
        }
        
        switch state {
        case .idle:
            return DS.color.success.opacity(0.3)
        case .listening:
            return DS.color.border.opacity(0.38)
        case .waiting:
            return DS.color.accent.opacity(0.22)
        case .thinking:
            return DS.color.accent.opacity(0.22)
        case .speaking:
            return DS.color.success.opacity(0.28)
        case .warning:
            return DS.color.warning.opacity(0.26)
        case .failed:
            return DS.color.danger.opacity(0.26)
        }
    }
    
    // MARK: - 波形动画
    
    private func barScaleFactor(at index: Int, wavePhase: Double) -> CGFloat {
        switch state {
        case .idle:
            return 1.0
        case .listening:
            return animatedBarValue(at: index, wavePhase: wavePhase, min: 0.72, max: 1.18)
        case .waiting:
            return animatedBarValue(at: index, wavePhase: wavePhase, min: 0.82, max: 1.08)
        case .thinking:
            return animatedBarValue(at: index, wavePhase: wavePhase, min: 0.9, max: 1.03)
        case .speaking:
            return animatedBarValue(at: index, wavePhase: wavePhase, min: 0.82, max: 1.12)
        case .warning:
            return animatedBarValue(at: index, wavePhase: wavePhase, min: 0.94, max: 1.02)
        case .failed:
            return 1.0
        }
    }
    
    private func barOpacity(at index: Int, wavePhase: Double) -> Double {
        switch state {
        case .idle:
            return 1.0
        case .listening:
            return animatedBarOpacity(at: index, wavePhase: wavePhase, min: 0.56, max: 1.0)
        case .waiting:
            return animatedBarOpacity(at: index, wavePhase: wavePhase, min: 0.72, max: 0.92)
        case .thinking:
            return animatedBarOpacity(at: index, wavePhase: wavePhase, min: 0.76, max: 0.88)
        case .speaking:
            return animatedBarOpacity(at: index, wavePhase: wavePhase, min: 0.64, max: 0.96)
        case .warning:
            return animatedBarOpacity(at: index, wavePhase: wavePhase, min: 0.8, max: 0.92)
        case .failed:
            return 0.82
        }
    }
    
    private func animatedBarValue(at index: Int, wavePhase: Double, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        let offset = phaseOffsets[Swift.min(index, phaseOffsets.count - 1)]
        let normalized = (sin((wavePhase * 1.9) - offset) + 1) / 2
        return minValue + (maxValue - minValue) * normalized
    }
    
    private func animatedBarOpacity(at index: Int, wavePhase: Double, min minValue: Double, max maxValue: Double) -> Double {
        let offset = phaseOffsets[Swift.min(index, phaseOffsets.count - 1)]
        let normalized = (sin((wavePhase * 1.9) - offset) + 1) / 2
        return minValue + (maxValue - minValue) * normalized
    }
    
    private func waveformPhase(for date: Date) -> Double {
        date.timeIntervalSinceReferenceDate * 2.4
    }
    
    private func breathingPhase(for date: Date) -> Double {
        date.timeIntervalSinceReferenceDate * 2.0
    }
    
    private func triggerCompletionPulse() {
        completionPulse = 0
        withAnimation(.spring(response: 0.26, dampingFraction: 0.8)) {
            completionPulse = 0.12
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(.easeOut(duration: 0.22)) {
                completionPulse = 0
            }
        }
    }
}

#Preview("录音胶囊") {
    VStack(spacing: 20) {
        RecordingBarView(state: .listening, preset: .standard, colorScheme: .light)
        RecordingBarView(state: .thinking, preset: .standard, colorScheme: .light)
        RecordingBarView(state: .idle, preset: .standard, colorScheme: .light)
        RecordingBarView(state: .listening, preset: .minimal, colorScheme: .light)
        RecordingBarView(state: .idle, preset: .minimal, colorScheme: .light)
    }
    .padding(40)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(DS.color.background)
}
