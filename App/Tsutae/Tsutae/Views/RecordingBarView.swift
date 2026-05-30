import SwiftUI
import TsutaeCore

/// 极简录音条（Leader HUD 折叠态）
/// 对应设计图: docs/design/mockups/recording-bar-collapsed-v1.png
struct RecordingBarView: View {
    
    let state: AppState
    let preset: DS.recordingBar.Preset
    
    @State private var amplitudes: [CGFloat]
    @State private var timer: Timer?
    
    private var layout: DS.recordingBar.Layout {
        DS.recordingBar.layout(for: preset)
    }
    
    init(
        state: AppState,
        preset: DS.recordingBar.Preset = DS.recordingBar.defaultPreset
    ) {
        self.state = state
        self.preset = preset
        _amplitudes = State(initialValue: Array(repeating: 0.1, count: DS.recordingBar.layout(for: preset).barCount))
    }
    
    var body: some View {
        HStack(spacing: layout.contentSpacing) {
            // 状态圆点（带发光效果）
            Circle()
                .fill(stateColor)
                .frame(width: layout.statusDot, height: layout.statusDot)
                .shadow(color: stateColor.opacity(0.9), radius: 4, x: 0, y: 0)
                .shadow(color: stateColor.opacity(0.6), radius: 8, x: 0, y: 0)
            
            // 波形
            waveformView
                .frame(height: layout.waveformHeight)
        }
        .padding(.horizontal, layout.horizontalPadding)
        .padding(.vertical, layout.verticalPadding)
        .frame(width: layout.width, height: layout.height)
        // 苹果风格玻璃背景
        .background(
            Capsule()
                .fill(.black.opacity(0.25))
                .background(.ultraThinMaterial.opacity(0.8))
        )
        .clipShape(Capsule())
        .overlay(
            Capsule()
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
        .onAppear {
            startAnimation()
        }
        .onDisappear {
            stopAnimation()
        }
    }
    
    // MARK: - 波形
    
    private var waveformView: some View {
        HStack(alignment: .center, spacing: layout.barSpacing) {
            ForEach(0..<amplitudes.count, id: \.self) { index in
                RoundedRectangle(cornerRadius: layout.barCornerRadius)
                    .fill(stateColor)
                    .frame(
                        width: layout.barWidth,
                        height: max(layout.minBarHeight, amplitudes[index] * layout.maxBarHeight)
                    )
            }
        }
    }
    
    private var stateColor: Color {
        switch state {
        case .idle: return DS.color.stateIdle
        case .listening: return DS.color.brandBlue
        case .thinking: return DS.color.stateThinking
        case .speaking: return DS.color.stateSpeaking
        }
    }
    
    // MARK: - 动画
    
    private func startAnimation() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
            Task { @MainActor in
                withAnimation(.easeInOut(duration: 0.08)) {
                    updateAmplitudes()
                }
            }
        }
    }
    
    private func stopAnimation() {
        timer?.invalidate()
        timer = nil
    }
    
    private func updateAmplitudes() {
        let phase = Date().timeIntervalSince1970 * 3
        
        for i in 0..<amplitudes.count {
            let normalizedIndex = CGFloat(i) / CGFloat(amplitudes.count - 1)
            
            // 中间高、两边低的包络
            let envelope = sin(normalizedIndex * .pi)
            
            // 多层噪声叠加
            let wave1 = sin(phase + Double(i) * 0.5) * 0.25
            let wave2 = sin(phase * 1.5 + Double(i) * 0.3) * 0.15
            let noise = Double.random(in: -0.05...0.05)
            
            let base = 0.1 + envelope * 0.45
            amplitudes[i] = max(0.08, min(1.0, base + CGFloat(wave1 + wave2 + noise)))
        }
    }
}

#Preview("录音条预览") {
    ZStack {
        Color.black.opacity(0.3).ignoresSafeArea()
        VStack(spacing: 20) {
            RecordingBarView(state: .listening, preset: .compact)
            RecordingBarView(state: .listening, preset: .medium)
            RecordingBarView(state: .listening, preset: .large)
        }
    }
}
