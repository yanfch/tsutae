import SwiftUI

/// Maple Mono 连字文字组件
/// 利用 Maple Mono 的 OpenType 连字特性，让状态标签更美观
///
/// 可用连字示例:
/// - 标签: [LISTENING] [DONE] [ERROR] [TODO] [FIXME]
/// - 箭头: -> => <-> |>
/// - 比较: != == <= >=
/// - 其他: ... ### ~~> <!-- -->
struct MapleText: View {
    
    enum Style {
        /// 普通等宽文字
        case regular
        /// 状态标签（带背景 pill）
        case tag
        /// 状态标签（小号）
        case tagSmall
        /// 代码片段
        case code
        /// 快捷键显示
        case keycap
    }
    
    let text: String
    let style: Style
    
    init(_ text: String, style: Style = .regular) {
        self.text = text
        self.style = style
    }
    
    var body: some View {
        switch style {
        case .regular:
            regularText
        case .tag:
            tagText
        case .tagSmall:
            tagSmallText
        case .code:
            codeText
        case .keycap:
            keycapText
        }
    }
    
    // MARK: - 普通等宽文字
    
    private var regularText: some View {
        Text(text)
            .font(DS.font.mono(.body))
            .foregroundStyle(DS.color.soft)
    }
    
    // MARK: - 状态标签
    
    private var tagText: some View {
        Text(text)
            .font(DS.font.mono(.caption, weight: .medium))
            .foregroundStyle(DS.color.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(DS.color.accent.opacity(0.08))
            )
            .overlay(
                Capsule()
                    .strokeBorder(DS.color.accent.opacity(0.18), lineWidth: 1)
            )
    }
    
    // MARK: - 小号状态标签
    
    private var tagSmallText: some View {
        Text(text)
            .font(DS.font.mono(size: 10, weight: .medium))
            .foregroundStyle(DS.color.muted)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(DS.color.surface2)
            )
            .overlay(
                Capsule()
                    .strokeBorder(DS.color.borderSoft.opacity(0.4), lineWidth: 0.5)
            )
    }
    
    // MARK: - 代码片段
    
    private var codeText: some View {
        Text(text)
            .font(DS.font.mono(.caption))
            .foregroundStyle(DS.color.soft)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(DS.color.surface2.opacity(0.6))
            )
    }
    
    // MARK: - 快捷键显示
    
    private var keycapText: some View {
        Text(text)
            .font(DS.font.mono(size: 11))
            .foregroundStyle(DS.color.soft)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(DS.color.surface.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(DS.color.borderSoft.opacity(0.4), lineWidth: 1)
            )
    }
}

// MARK: - 连字效果预览

#Preview("Maple Mono 连字效果") {
    VStack(alignment: .leading, spacing: 24) {
        // 状态标签连字
        VStack(alignment: .leading, spacing: 12) {
            Text("状态标签")
                .font(DS.font.display(.headline))
            
            HStack(spacing: 12) {
                MapleText("[LISTENING]", style: .tag)
                MapleText("[DONE]", style: .tag)
                MapleText("[ERROR]", style: .tag)
                MapleText("[TODO]", style: .tag)
            }
            
            HStack(spacing: 8) {
                MapleText("[INFO]", style: .tagSmall)
                MapleText("[WARN]", style: .tagSmall)
                MapleText("[DEBUG]", style: .tagSmall)
                MapleText("[FIXME]", style: .tagSmall)
            }
        }
        
        // 箭头和操作符连字
        VStack(alignment: .leading, spacing: 12) {
            Text("箭头和操作符")
                .font(DS.font.display(.headline))
            
            HStack(spacing: 16) {
                MapleText("->", style: .code)
                MapleText("=>", style: .code)
                MapleText("<->", style: .code)
                MapleText("|>", style: .code)
                MapleText("<!--", style: .code)
                MapleText("-->", style: .code)
            }
            
            HStack(spacing: 16) {
                MapleText("!=", style: .code)
                MapleText("==", style: .code)
                MapleText("<=", style: .code)
                MapleText(">=", style: .code)
                MapleText("===", style: .code)
                MapleText("!==", style: .code)
            }
        }
        
        // 快捷键显示
        VStack(alignment: .leading, spacing: 12) {
            Text("快捷键")
                .font(DS.font.display(.headline))
            
            HStack(spacing: 10) {
                MapleText("⌥R", style: .keycap)
                MapleText("⌘↩", style: .keycap)
                MapleText("Esc", style: .keycap)
                MapleText("⌘V", style: .keycap)
                MapleText("⌘C", style: .keycap)
            }
        }
        
        // 混合使用示例
        VStack(alignment: .leading, spacing: 12) {
            Text("混合使用")
                .font(DS.font.display(.headline))
            
            HStack(spacing: 8) {
                MapleText("[DONE]", style: .tag)
                Text("Dispatched -> clipboard")
                    .font(DS.font.mono(.caption))
                    .foregroundStyle(DS.color.muted)
                MapleText("⌘V", style: .keycap)
            }
        }
    }
    .padding(40)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(DS.color.background)
}

#Preview("暗色模式") {
    VStack(alignment: .leading, spacing: 24) {
        HStack(spacing: 12) {
            MapleText("[LISTENING]", style: .tag)
            MapleText("[DONE]", style: .tag)
            MapleText("[ERROR]", style: .tag)
        }
        
        HStack(spacing: 10) {
            MapleText("⌥R", style: .keycap)
            MapleText("⌘↩", style: .keycap)
            MapleText("Esc", style: .keycap)
        }
        
        HStack(spacing: 16) {
            MapleText("->", style: .code)
            MapleText("=>", style: .code)
            MapleText("!=", style: .code)
        }
    }
    .padding(40)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(DS.color.backgroundDark)
    .preferredColorScheme(.dark)
}
