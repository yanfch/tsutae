import SwiftUI

/// tsutae 设计系统 — 纸感、低饱和、安静克制的 macOS sidecar
/// 对应设计: docs/design/mockups/tsutae-macos-concept-6.html
///
/// 设计原则:
/// - 大面积纯色背景，不做玻璃和高饱和渐变
/// - 细线框 + 纸感表面，标题比正文更有温度
/// - 强调色只给 active item、button、recording 状态
enum DS {
    
    // MARK: - 颜色
    
    enum color {
        // --- 浅色模式 ---
        
        /// 强调色 / 品牌主色 #2f6b5f（松针绿）
        static let accent = SwiftUI.Color(red: 0x2F/255, green: 0x6B/255, blue: 0x5F/255)
        
        /// 强调色浅变体 #4b8579（hover / 次级）
        static let accentLight = SwiftUI.Color(red: 0x4B/255, green: 0x85/255, blue: 0x79/255)
        
        /// 页面背景（奶油纸感）
        static let background = SwiftUI.Color(red: 0xFF/255, green: 0xFD/255, blue: 0xF3/255)
        
        /// 表面色 #fffdf3
        static let surface = SwiftUI.Color(red: 0xFF/255, green: 0xFD/255, blue: 0xF3/255)
        
        /// 表面色层级 2
        static let surface2 = SwiftUI.Color(red: 0xF2/255, green: 0xF1/255, blue: 0xDF/255)
        
        /// 表面色层级 3
        static let surface3 = SwiftUI.Color(red: 0xE7/255, green: 0xE4/255, blue: 0xD0/255)
        
        /// 主文字色 #1f2a24
        static let foreground = SwiftUI.Color(red: 0x1F/255, green: 0x2A/255, blue: 0x24/255)
        
        /// 次要文字色 #66756b
        static let muted = SwiftUI.Color(red: 0x66/255, green: 0x75/255, blue: 0x6B/255)
        
        /// 柔和文字色 #4b5b51
        static let soft = SwiftUI.Color(red: 0x4B/255, green: 0x5B/255, blue: 0x51/255)
        
        /// 边框色 #97a391
        static let border = SwiftUI.Color(red: 0x97/255, green: 0xA3/255, blue: 0x91/255)
        
        /// 柔和边框色
        static let borderSoft = SwiftUI.Color(red: 0xC3/255, green: 0xC9/255, blue: 0xBF/255)
        
        /// 成功状态 #2d6e10
        static let success = SwiftUI.Color(red: 0x2D/255, green: 0x6E/255, blue: 0x10/255)
        
        /// 警告状态 #a16207
        static let warning = SwiftUI.Color(red: 0xA1/255, green: 0x62/255, blue: 0x07/255)
        
        /// 危险/错误状态 #d44010
        static let danger = SwiftUI.Color(red: 0xD4/255, green: 0x40/255, blue: 0x10/255)
        
        // --- 暗色模式（松烟墨纸面）---
        
        /// 暗色背景 #16201c
        static let backgroundDark = SwiftUI.Color(red: 0x16/255, green: 0x20/255, blue: 0x1C/255)
        
        /// 暗色表面色
        static let surfaceDark = SwiftUI.Color(red: 0x1D/255, green: 0x28/255, blue: 0x23/255)
        
        /// 暗色卡片
        static let cardDark = SwiftUI.Color(red: 0x24/255, green: 0x30/255, blue: 0x2A/255)
        
        /// 暗色主文字
        static let foregroundDark = SwiftUI.Color(red: 0xF2/255, green: 0xF2/255, blue: 0xE9/255)
        
        /// 暗色次要文字
        static let mutedDark = SwiftUI.Color(red: 0xB8/255, green: 0xC9/255, blue: 0xC0/255)
        
        // --- 兼容旧代码的映射 ---
        
        /// 兼容：brandBlue 现在是 accent
        static let brandBlue = accent
        
        /// 兼容：brandBlueDeep
        static let brandBlueDeep = accent
        
        /// 状态色 - 待机
        static let stateIdle = muted
        
        /// 状态色 - 识别中
        static let stateListening = accent
        
        /// 状态色 - 处理中
        static let stateThinking = warning
        
        /// 状态色 - 播放中
        static let stateSpeaking = success
        
        /// 状态色 - 错误
        static let stateError = danger
        
        /// 设置页背景 - 亮色
        static let settingsBgLight = surface2
        
        /// 设置页背景 - 暗色
        static let settingsBgDark = backgroundDark
        
        /// 卡片背景 - 暗色
        static let cardBgDark = cardDark
    }
    
    // MARK: - 圆角
    
    enum radius {
        /// 大胶囊 / Hero 区域
        static let xl: CGFloat = 28
        
        /// 卡片 / 浮窗
        static let lg: CGFloat = 20
        
        /// 中等容器
        static let md: CGFloat = 12
        
        /// 小控件
        static let sm: CGFloat = 8
        
        // 兼容旧代码
        static let hud: CGFloat = lg
        static let card: CGFloat = md
        static let row: CGFloat = sm
    }
    
    // MARK: - 阴影
    
    enum shadow {
        /// 主阴影（松针绿调）
        static let main = SwiftUI.Color(red: 0x2F/255, green: 0x6B/255, blue: 0x5F/255).opacity(0.08)
        
        /// 轻阴影
        static let soft = SwiftUI.Color(red: 0x2F/255, green: 0x6B/255, blue: 0x5F/255).opacity(0.05)
    }
    
    // MARK: - 尺寸
    
    enum size {
        /// Leader HUD 展开态宽度
        static let hudWidth: CGFloat = 470
    }
    
    // MARK: - 字体
    
    /// Maple Mono 字体配置
    /// 文档: https://github.com/subframe7536/maple-font
    ///
    /// 安装方式:
    /// ```sh
    /// brew install --cask font-maple-mono-nf-cn
    /// ```
    ///
    /// 字体特性:
    /// - 圆角字形设计，与纸感风格完美搭配
    /// - 2:1 中英文等宽比例，混排整齐
    /// - 变量字体格式，支持无限字重
    /// - 丰富的 OpenType 连字和样式集
    enum font {
        
        // MARK: Maple Mono 字体名常量
        
        /// Maple Mono NF CN 家族名（Homebrew 安装后可用）
        private static let mapleFamily = "Maple Mono NF CN"
        
        /// Maple Mono NF CN 各字重 PostScript 名
        private static let mapleWeights: [Font.Weight: String] = [
            .light: "MapleMono-NF-CN-Light",
            .regular: "MapleMono-NF-CN-Regular",
            .medium: "MapleMono-NF-CN-Medium",
            .semibold: "MapleMono-NF-CN-SemiBold",
            .bold: "MapleMono-NF-CN-Bold",
            .heavy: "MapleMono-NF-CN-ExtraBold"
        ]
        
        // MARK: - 核心字体方法
        
        /// 展示/标题字体 — 衬线体，纸感气质
        /// 优先级: Iowan Old Style > Charter > Georgia
        static func display(_ style: SwiftUI.Font.TextStyle) -> SwiftUI.Font {
            if let iowan = NSFont(name: "IowanOldStyle-Bold", size: style.size) {
                return SwiftUI.Font(iowan)
            }
            if let charter = NSFont(name: "Charter-Bold", size: style.size) {
                return SwiftUI.Font(charter)
            }
            return SwiftUI.Font.custom("Georgia", size: style.size, relativeTo: style)
        }
        
        /// 正文字体 — SF Pro Text + 苹方（系统默认）
        static func body(_ style: SwiftUI.Font.TextStyle) -> SwiftUI.Font {
            .system(style, design: .default)
        }
        
        /// 等宽字体 — Maple Mono NF CN Regular
        /// 用于: 标签、badge、状态文字、代码展示
        static func mono(_ style: SwiftUI.Font.TextStyle) -> SwiftUI.Font {
            mono(style, weight: .regular)
        }
        
        /// 等宽字体 — Maple Mono NF CN 指定字重
        /// 用于: 需要不同粗细的等宽场景
        static func mono(_ style: SwiftUI.Font.TextStyle, weight: Font.Weight) -> SwiftUI.Font {
            let size = style.size
            
            // 1. 尝试 PostScript 名（最精确）
            if let psName = mapleWeights[weight],
               let maple = NSFont(name: psName, size: size) {
                return SwiftUI.Font(maple)
            }
            
            // 2. 尝试家族名 + 字重
            if let maple = NSFont(descriptor: NSFontDescriptor(fontAttributes: [
                .family: mapleFamily,
                .traits: [NSFontDescriptor.TraitKey.weight: nsFontWeight(weight)]
            ]), size: size) {
                return SwiftUI.Font(maple)
            }
            
            // 3. 回退到 SF Mono
            return .system(size: size, weight: weight, design: .monospaced)
        }
        
        /// 等宽字体 — Maple Mono NF CN 指定字号
        /// 用于: 需要精确控制字号的场景
        static func mono(size: CGFloat, weight: Font.Weight = .regular) -> SwiftUI.Font {
            if let psName = mapleWeights[weight],
               let maple = NSFont(name: psName, size: size) {
                return SwiftUI.Font(maple)
            }
            return .system(size: size, weight: weight, design: .monospaced)
        }
        
        /// 圆体 — 适合工具感
        static func rounded(_ style: SwiftUI.Font.TextStyle) -> SwiftUI.Font {
            .system(style, design: .rounded)
        }
        
        // MARK: - Maple Mono OpenType 特性配置
        
        /// 创建带 OpenType 特性的 Maple Mono NSFont
        /// - Parameters:
        ///   - size: 字号
        ///   - weight: 字重
        ///   - features: OpenType 特性字典
        /// - Returns: 配置好的 NSFont
        ///
        /// 可用特性:
        /// - `calt`: 上下文替代（连字）- 默认开启
        /// - `liga`: 标准连字
        /// - `cv01`-`cv99`: 字符变体
        /// - `ss01`-`ss11`: 样式集
        ///
        /// 示例:
        /// ```swift
        /// // 启用斜体连字
        /// let font = DS.font.mapleMono(size: 14, features: ["calt": 1])
        /// 
        /// // 启用样式集 05（特殊标签连字）
        /// let font = DS.font.mapleMono(size: 14, features: ["ss05": 1])
        /// ```
        static func mapleMono(
            size: CGFloat,
            weight: Font.Weight = .regular,
            features: [String: Int] = [:]
        ) -> NSFont? {
            guard let psName = mapleWeights[weight],
                  let baseFont = NSFont(name: psName, size: size) else {
                return nil
            }
            
            guard !features.isEmpty else { return baseFont }
            
            // 构建 OpenType 特性数组
            var otFeatures: [[NSFontDescriptor.FeatureKey: Int]] = []
            for (feature, value) in features {
                // 将特性标签转换为 FourCharCode
                if let tag = featureToTag(feature) {
                    otFeatures.append([
                        .typeIdentifier: Int(tag),
                        .selectorIdentifier: value
                    ])
                }
            }
            
            let descriptor = baseFont.fontDescriptor.addingAttributes([
                .featureSettings: otFeatures
            ])
            
            return NSFont(descriptor: descriptor, size: size)
        }
        
        /// 将特性字符串标签转换为 FourCharCode
        private static func featureToTag(_ tag: String) -> UInt32? {
            guard tag.count == 4 else { return nil }
            var result: UInt32 = 0
            for char in tag.utf8 {
                result = (result << 8) | UInt32(char)
            }
            return result
        }
        
        /// SwiftUI Font.Weight 转 NSFont 字重值
        private static func nsFontWeight(_ weight: Font.Weight) -> NSFont.Weight {
            switch weight {
            case .ultraLight: return .ultraLight
            case .thin: return .thin
            case .light: return .light
            case .regular: return .regular
            case .medium: return .medium
            case .semibold: return .semibold
            case .bold: return .bold
            case .heavy: return .heavy
            case .black: return .black
            default: return .regular
            }
        }
        
        // MARK: - 便捷属性
        
        /// Maple Mono Regular 等宽字体（用于标签、badge）
        static var monoRegular: SwiftUI.Font {
            mono(.body)
        }
        
        /// Maple Mono Medium 等宽字体（用于强调标签）
        static var monoMedium: SwiftUI.Font {
            mono(.body, weight: .medium)
        }
        
        /// Maple Mono Bold 等宽字体（用于标题标签）
        static var monoBold: SwiftUI.Font {
            mono(.body, weight: .bold)
        }
        
        /// 检查 Maple Mono 是否已安装
        static var isMapleMonoInstalled: Bool {
            NSFont(name: mapleFamily, size: 12) != nil
        }
    }
    
    // MARK: - 录音条（新设计 - 纸感胶囊）
    
    enum recordingBar {
        static let presetDefaultsKey = "recordingBarPreset"
        
        enum Preset: String, CaseIterable {
            case standard  // 标准胶囊
            case minimal = "compact"  // 保持旧存储值兼容
            
            var title: String {
                switch self {
                case .standard: return "标准"
                case .minimal: return "极简"
                }
            }
        }
        
        struct Layout {
            let height: CGFloat
            let cornerRadius: CGFloat
            let horizontalPadding: CGFloat
            let verticalPadding: CGFloat
            let contentSpacing: CGFloat
            let leadingClusterSpacing: CGFloat
            let showsStatusLabel: Bool
            let showsKeycap: Bool
            let statusWidth: CGFloat
            let keycapWidth: CGFloat
            let dotGlowSize: CGFloat
            let dotSize: CGFloat
            let waveformHeight: CGFloat
            let waveformHeights: [CGFloat]
            let barWidth: CGFloat
            let barSpacing: CGFloat
            let barCornerRadius: CGFloat
            let statusFontSize: CGFloat
            let keycapHorizontalPadding: CGFloat
            let keycapVerticalPadding: CGFloat
            let keycapFontSize: CGFloat
            
            var barCount: Int {
                waveformHeights.count
            }
            
            var waveformWidth: CGFloat {
                CGFloat(barCount) * barWidth + CGFloat(max(barCount - 1, 0)) * barSpacing
            }
            
            var leadingSlotWidth: CGFloat {
                dotGlowSize + leadingClusterSpacing + waveformWidth
            }
            
            var width: CGFloat {
                (horizontalPadding * 2)
                + leadingSlotWidth
                + (showsStatusLabel ? contentSpacing + statusWidth : 0)
                + (showsKeycap ? contentSpacing + keycapWidth : 0)
            }
            
            init(preset: Preset) {
                switch preset {
                case .standard:
                    height = 38
                    cornerRadius = 999
                    horizontalPadding = 14
                    verticalPadding = 10
                    contentSpacing = 8
                    leadingClusterSpacing = 6
                    showsStatusLabel = true
                    showsKeycap = true
                    statusWidth = 60
                    keycapWidth = 48
                    dotGlowSize = 18
                    dotSize = 10
                    waveformHeight = 24
                    waveformHeights = [10, 18, 13, 22, 14, 20, 12, 16, 11]
                    barWidth = 4
                    barSpacing = 5
                    barCornerRadius = 2
                    statusFontSize = 13
                    keycapHorizontalPadding = 10
                    keycapVerticalPadding = 7
                    keycapFontSize = 11
                    
                case .minimal:
                    height = 32
                    cornerRadius = 16
                    horizontalPadding = 17
                    verticalPadding = 8
                    contentSpacing = 0
                    leadingClusterSpacing = 6
                    showsStatusLabel = false
                    showsKeycap = false
                    statusWidth = 0
                    keycapWidth = 0
                    dotGlowSize = 16
                    dotSize = 8
                    waveformHeight = 18
                    waveformHeights = [6, 12, 7, 14, 8, 13, 7]
                    barWidth = 4
                    barSpacing = 4
                    barCornerRadius = 2
                    statusFontSize = 13
                    keycapHorizontalPadding = 10
                    keycapVerticalPadding = 7
                    keycapFontSize = 11
                }
            }
        }
        
        static let defaultPreset: Preset = .standard
        
        static var currentPreset: Preset {
            let rawValue = UserDefaults.standard.string(forKey: presetDefaultsKey)
            return rawValue.flatMap(Preset.init(rawValue:)) ?? defaultPreset
        }
        
        static func layout(for preset: Preset) -> Layout {
            Layout(preset: preset)
        }
        
        static var current: Layout {
            Layout(preset: currentPreset)
        }
    }
}

// MARK: - Font.TextStyle 扩展

extension SwiftUI.Font.TextStyle {
    var size: CGFloat {
        switch self {
        case .largeTitle: return 34
        case .title: return 28
        case .title2: return 22
        case .title3: return 20
        case .headline: return 17
        case .body: return 17
        case .callout: return 16
        case .subheadline: return 15
        case .footnote: return 13
        case .caption: return 12
        case .caption2: return 11
        @unknown default: return 17
        }
    }
}
