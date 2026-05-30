import SwiftUI

/// tsutae 设计系统 — 单一事实来源
/// 对应文档: docs/design/design-system.md
///
/// 用法: DS.color.brandBlue, DS.radius.card, DS.size.hudWidth ...
enum DS {
    
    // MARK: - 颜色
    
    enum color {
        /// 品牌主色 / 默认强调色 #2B8CFF
        static let brandBlue = SwiftUI.Color(
            red: 0x2B / 255,
            green: 0x8C / 255,
            blue: 0xFF / 255
        )
        
        /// 品牌色深变体 #1B6FE0（渐变底端 / 暗色模式）
        static let brandBlueDeep = SwiftUI.Color(
            red: 0x1B / 255,
            green: 0x6F / 255,
            blue: 0xE0 / 255
        )
        
        /// 状态色 - 待机（系统次要灰）
        static let stateIdle = SwiftUI.Color.secondary
        
        /// 状态色 - 转写/处理中（固定语义色，不随主题）
        static let stateThinking = SwiftUI.Color.orange
        
        /// 状态色 - TTS 播放中（固定语义色，不随主题）
        static let stateSpeaking = SwiftUI.Color.green
        
        /// 状态色 - 错误（固定语义色，不随主题）
        static let stateError = SwiftUI.Color.red
        
        // listening 状态 = 当前 accentColor，从环境读取，不在这里定义
        
        /// 设置页背景 - 亮色
        static let settingsBgLight = SwiftUI.Color(red: 0xF2/255, green: 0xF2/255, blue: 0xF4/255)
        
        /// 设置页背景 - 暗色
        static let settingsBgDark = SwiftUI.Color(red: 0x1C/255, green: 0x1C/255, blue: 0x1E/255)
        
        /// 卡片背景 - 暗色
        static let cardBgDark = SwiftUI.Color(red: 0x2C/255, green: 0x2C/255, blue: 0x2E/255)
    }
    
    // MARK: - 圆角
    
    enum radius {
        /// HUD 浮窗
        static let hud: CGFloat = 16
        /// 设置页卡片
        static let card: CGFloat = 12
        /// 行 / 控件
        static let row: CGFloat = 8
    }
    
    // MARK: - 尺寸
    
    enum size {
        /// Leader HUD 展开态宽度
        static let hudWidth: CGFloat = 360
    }
    
    enum recordingBar {
        static let presetDefaultsKey = "recordingBarPreset"
        
        enum Preset: String, CaseIterable {
            case compact
            case medium
            case large
            
            var title: String {
                switch self {
                case .compact: return "小"
                case .medium: return "中"
                case .large: return "大"
                }
            }
            
            var scale: CGFloat {
                switch self {
                case .compact: return 1.0
                case .medium: return 200.0 / 180.0
                case .large: return 220.0 / 180.0
                }
            }
        }
        
        struct Layout {
            let width: CGFloat
            let height: CGFloat
            let contentSpacing: CGFloat
            let horizontalPadding: CGFloat
            let verticalPadding: CGFloat
            let statusDot: CGFloat
            let waveformHeight: CGFloat
            let barCount: Int
            let barWidth: CGFloat
            let barSpacing: CGFloat
            let barCornerRadius: CGFloat
            let minBarHeight: CGFloat
            let maxBarHeight: CGFloat
            
            init(preset: Preset) {
                let scale = preset.scale
                
                width = 180 * scale
                height = 36 * scale
                contentSpacing = 6 * scale
                horizontalPadding = 6 * scale
                verticalPadding = 8 * scale
                statusDot = 7 * scale
                waveformHeight = 16 * scale
                barCount = 20
                barWidth = max(2, 3 * scale)
                barSpacing = max(1.5, 2 * scale)
                barCornerRadius = max(1, scale)
                minBarHeight = max(3, 3 * scale)
                maxBarHeight = 15 * scale
            }
        }
        
        static let defaultPreset: Preset = .compact
        
        static var currentPreset: Preset {
            let rawValue = UserDefaults.standard.string(forKey: presetDefaultsKey)
            return rawValue.flatMap(Preset.init(rawValue:)) ?? defaultPreset
        }
        
        static var current: Layout {
            Layout(preset: currentPreset)
        }
        
        static func layout(for preset: Preset) -> Layout {
            Layout(preset: preset)
        }
    }
    
    // MARK: - 字体辅助
    
    enum font {
        /// HUD / 录音条 / 品牌感处 — SF Pro Rounded
        static func rounded(_ style: SwiftUI.Font.TextStyle) -> SwiftUI.Font {
            .system(style, design: .rounded)
        }
        
        /// 时长 / 数字 / 波形旁 — SF Mono
        static func mono(_ style: SwiftUI.Font.TextStyle) -> SwiftUI.Font {
            .system(style, design: .monospaced)
        }
    }
}
