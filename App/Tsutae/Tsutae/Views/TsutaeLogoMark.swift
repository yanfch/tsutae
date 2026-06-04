import SwiftUI

/// tsutae 品牌图标 — 声波被折成一笔，送往别处的动作感
/// 对应设计: docs/design/mockups/tsutae-macos-concept-6.html
struct TsutaeLogoMark: View {
    
    enum Style {
        /// 菜单栏/状态栏小图标
        case menuBar
        /// 应用图标
        case appIcon
        /// 品牌展示大图标
        case brand
        /// Voice bar 内嵌小图标
        case inline
    }
    
    let style: Style
    
    init(_ style: Style = .brand) {
        self.style = style
    }
    
    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let scale = size / 52 // 基准尺寸 52
            
            ZStack {
                // 主体圆角方块
                RoundedRectangle(cornerRadius: 18 * scale, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                DS.color.accent,
                                DS.color.accentLight
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                // 声波笔画 - 上半部分：倾斜的竖线
                RoundedRectangle(cornerRadius: 999 * scale, style: .continuous)
                    .fill(DS.color.surface)
                    .frame(width: 10 * scale, height: 30 * scale)
                    .rotationEffect(.degrees(18))
                    .offset(x: -2 * scale, y: -4 * scale)
                
                // 声波笔画 - 下半部分：横线
                RoundedRectangle(cornerRadius: 999 * scale, style: .continuous)
                    .fill(DS.color.surface)
                    .frame(width: 26 * scale, height: 10 * scale)
                    .offset(x: 2 * scale, y: 8 * scale)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - 菜单栏专用版本（单色，适配深色菜单栏）

extension TsutaeLogoMark {
    
    /// 菜单栏单色版本 - 使用 template color
    struct MenuBarIcon: View {
        var body: some View {
            Image(nsImage: createMenuBarIcon())
                .renderingMode(.template)
        }
        
        private func createMenuBarIcon() -> NSImage {
            let size = NSSize(width: 18, height: 18)
            let image = NSImage(size: size, flipped: false) { rect in
                let ctx = NSGraphicsContext.current!.cgContext
                
                // 背景圆角方块
                let bgRect = rect.insetBy(dx: 1, dy: 1)
                let bgPath = CGPath(
                    roundedRect: bgRect,
                    cornerWidth: 5,
                    cornerHeight: 5,
                    transform: nil
                )
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.addPath(bgPath)
                ctx.fillPath()
                
                // 声波竖线
                ctx.setStrokeColor(NSColor.white.cgColor)
                ctx.setLineWidth(2.0)
                ctx.setLineCap(.round)
                
                let centerX = rect.midX
                let centerY = rect.midY
                
                // 竖线（旋转）
                ctx.saveGState()
                ctx.translateBy(x: centerX - 1, y: centerY - 2)
                ctx.rotate(by: .pi / 180 * 18)
                ctx.move(to: CGPoint(x: 0, y: -9))
                ctx.addLine(to: CGPoint(x: 0, y: 9))
                ctx.strokePath()
                ctx.restoreGState()
                
                // 横线
                ctx.move(to: CGPoint(x: centerX - 7, y: centerY + 2))
                ctx.addLine(to: CGPoint(x: centerX + 7, y: centerY + 2))
                ctx.strokePath()
                
                return true
            }
            image.isTemplate = true
            return image
        }
    }
}

#Preview("品牌图标") {
    VStack(spacing: 20) {
        HStack(spacing: 20) {
            TsutaeLogoMark(.brand)
                .frame(width: 52, height: 52)
            
            TsutaeLogoMark(.appIcon)
                .frame(width: 40, height: 40)
            
            TsutaeLogoMark(.inline)
                .frame(width: 24, height: 24)
        }
        
        TsutaeLogoMark.MenuBarIcon()
    }
    .padding(40)
    .background(DS.color.surface)
}
