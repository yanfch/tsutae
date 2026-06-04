import SwiftUI
import TsutaeCore

/// 纸感录音胶囊 — 共用一套骨架，按 preset 切换标准 / 极简
struct RecordingBarView: View {
    
    let state: AppState
    let preset: DS.recordingBar.Preset
    let colorScheme: ColorScheme
    
    // 动画延迟：从左到右依次增加
    private let delays: [Double] = [0, 0.08, 0.16, 0.24, 0.32, 0.4, 0.48, 0.56, 0.64]
    
    @State private var scaleFactors: [CGFloat] = [0.72, 0.96, 0.78, 1.0, 0.82, 0.94, 0.76, 0.9, 0.74]
    @State private var opacities: [Double] = [0.58, 0.88, 0.66, 1.0, 0.72, 0.9, 0.64, 0.84, 0.6]
    @State private var breathPhase: Double = 0
    @State private var breathTimer: Timer?
    
    private var layout: DS.recordingBar.Layout {
        DS.recordingBar.layout(for: preset)
    }
    
    init(
        state: AppState,
        preset: DS.recordingBar.Preset = DS.recordingBar.defaultPreset,
        colorScheme: ColorScheme = .light
    ) {
        self.state = state
        self.preset = preset
        self.colorScheme = colorScheme
    }
    
    var body: some View {
        HStack(spacing: layout.contentSpacing) {
            leadingCluster
            
            if layout.showsStatusLabel {
                statusLabel
                    .frame(width: layout.statusWidth, alignment: .center)
            }
            
            if layout.showsKeycap {
                keycapView
                    .frame(width: layout.keycapWidth)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, layout.horizontalPadding)
        .padding(.vertical, layout.verticalPadding)
        .frame(width: layout.width, height: layout.height)
        .background(backgroundShape.fill(backgroundColor))
        .overlay(
            backgroundShape
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.08),
                            Color.white.opacity(0.04),
                            Color.white.opacity(0.06)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
        )
        .shadow(color: shadowColor, radius: 10, x: 0, y: 4)
        .onAppear {
            startAnimations()
        }
        .onDisappear {
            stopAnimations()
        }
    }
    
    // MARK: - 布局片段
    
    private var backgroundShape: some InsettableShape {
        RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
    }
    
    private var leadingCluster: some View {
        HStack(spacing: layout.leadingClusterSpacing) {
            breathingDot
            waveformView
        }
    }
    
    // MARK: - 呼吸发光圆点
    
    private var breathingDot: some View {
        ZStack {
            Circle()
                .fill(stateColor.opacity(0.08))
                .frame(width: layout.dotGlowSize, height: layout.dotGlowSize)
                .scaleEffect(1.0 + sin(breathPhase) * 0.1)
                .opacity(0.6 + sin(breathPhase) * 0.2)
            
            if state == .idle && preset == .minimal {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(DS.color.success)
            } else {
                Circle()
                    .fill(stateColor)
                    .frame(width: layout.dotSize, height: layout.dotSize)
            }
        }
    }
    
    private var waveformView: some View {
        HStack(alignment: .center, spacing: layout.barSpacing) {
            ForEach(0..<layout.barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: layout.barCornerRadius, style: .continuous)
                    .fill(waveformColor)
                    .frame(width: layout.barWidth, height: layout.waveformHeights[index])
                    .scaleEffect(y: barScaleFactor(at: index))
                    .opacity(barOpacity(at: index))
            }
        }
        .frame(width: layout.waveformWidth, height: layout.waveformHeight, alignment: .leading)
    }
    
    // MARK: - 状态文字
    
    private var statusLabel: some View {
        Text(stateLabel)
            .font(.system(size: layout.statusFontSize, weight: .medium, design: .monospaced))
            .italic()
            .foregroundStyle(DS.color.foreground)
            .lineLimit(1)
    }
    
    // MARK: - 热键提示
    
    private var keycapView: some View {
        Text(keycapText)
            .font(.system(size: layout.keycapFontSize, weight: .regular, design: .monospaced))
            .italic()
            .foregroundStyle(state == .idle ? DS.color.success : DS.color.soft)
            .padding(.horizontal, layout.keycapHorizontalPadding)
            .padding(.vertical, layout.keycapVerticalPadding)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(state == .idle ? DS.color.success.opacity(0.1) : Color.white.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(state == .idle ? DS.color.success.opacity(0.3) : DS.color.border.opacity(0.38), lineWidth: 1)
            )
    }
    
    // MARK: - 计算属性
    
    private var stateLabel: String {
        switch state {
        case .idle: return "Done"
        case .listening: return "Listen"
        case .thinking: return "Think"
        case .speaking: return "Speak"
        }
    }
    
    private var stateSubLabel: String {
        switch state {
        case .idle: return "Ready"
        case .listening: return "zh / en auto"
        case .thinking: return "Transcribing..."
        case .speaking: return "Playing..."
        }
    }
    
    private var keycapText: String {
        switch state {
        case .idle: return "✓"
        case .listening: return "Esc"
        case .thinking: return "Esc"
        case .speaking: return "⌥R"
        }
    }
    
    // MARK: - 颜色
    
    private var backgroundColor: Color {
        colorScheme == .dark
            ? Color(red: 0x1B / 255, green: 0x25 / 255, blue: 0x21 / 255)
            : Color(red: 0xFF / 255, green: 0xFD / 255, blue: 0xF3 / 255)
    }
    
    private var shadowColor: Color {
        colorScheme == .dark
            ? .black.opacity(0.3)
            : DS.color.accent.opacity(0.08)
    }
    
    private var stateColor: Color {
        switch state {
        case .idle:
            return preset == .standard ? DS.color.accent : DS.color.success
        case .listening:
            return DS.color.accent
        case .thinking:
            return DS.color.accent
        case .speaking:
            return DS.color.success
        }
    }
    
    private var waveformColor: Color {
        switch state {
        case .idle, .listening, .thinking:
            return DS.color.accent
        case .speaking:
            return DS.color.success
        }
    }
    
    private func barScaleFactor(at index: Int) -> CGFloat {
        state == .idle ? 1.0 : scaleFactors[index]
    }
    
    private func barOpacity(at index: Int) -> Double {
        state == .idle ? 1.0 : opacities[index]
    }
    
    // MARK: - 动画
    
    private func startAnimations() {
        for i in 0..<layout.barCount {
            animateBar(at: i)
        }
        
        // 呼吸动画
        breathTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            Task { @MainActor in
                withAnimation(.linear(duration: 0.05)) {
                    breathPhase += 0.1
                }
            }
        }
    }
    
    private func animateBar(at index: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delays[index]) {
            withAnimation(
                .easeInOut(duration: 0.6)
                    .repeatForever(autoreverses: true)
            ) {
                scaleFactors[index] = 1.18
                opacities[index] = 1.0
            }
        }
    }
    
    private func stopAnimations() {
        breathTimer?.invalidate()
        breathTimer = nil
    }
}

#Preview("录音胶囊") {
    VStack(spacing: 20) {
        RecordingBarView(state: .listening, preset: .standard, colorScheme: .light)
        RecordingBarView(state: .listening, preset: .minimal, colorScheme: .light)
    }
    .padding(40)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(DS.color.background)
}
