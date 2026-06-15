# tsutae 设计系统规范

> 本文档把 `../ui-design.md` 里的视觉决策,整理成**开发可直接查、代码可直接映射**的规范。
> 配套:效果图见 `mockups/`,页面/交互定义见 `../ui-design.md`。
>
> 状态标记:✅ 已定 · 🟡 暂定(实现后校准) · ⬜ 待补充

## 0. 核心原则

1. **原生优先**:能用 SwiftUI 系统组件就用,不自己画。系统组件自带尺寸/间距/点击区/无障碍,不需要像素标注。
2. **token 走语义**:颜色/材质优先用系统语义(`.accentColor` / `.regularMaterial` / `.secondary`),自动适配亮暗模式。只有品牌色和自定义组件才写死数值。
3. **规范的最终形态是代码**:`DesignTokens.swift` 是单一事实来源,本文档是它的人类可读版。两者保持同步。

---

## 1. 颜色 ✅

### 品牌 / 强调色

| token | hex | 说明 |
|---|---|---|
| `brandBlue` | `#2B8CFF` | 品牌主色 + 默认强调色 |
| `brandBlueDeep` | `#1B6FE0` | 渐变底端 / 暗色变体 |

### 状态色

| token | hex | 跟随主题? |
|---|---|---|
| `stateIdle` | `#8A8A8E`(系统次要灰) | 否 |
| `stateListening` | = 当前强调色 | **是**(默认蓝,主题变则变) |
| `stateThinking` | `#FFB020` 琥珀 | 否(固定语义) |
| `stateSpeaking` | `#30D158`(systemGreen) | 否(固定语义) |
| `stateError` | `#FF453A`(systemRed) | 否(固定语义) |

规则:**只有 listening 跟随强调色;thinking/speaking/error 是固定语义色**,不能被主题色冲掉。语义色尽量映射到 Apple 系统色,自动适配亮暗。

### 设置页背景 / 卡片

| token | 亮色 | 暗色 |
|---|---|---|
| `settingsBg` | `#F2F2F4` | `#1C1C1E` |
| `cardBg` | 白(不透明) | `#2C2C2E` |
| `cardBorder` | 1px hairline | 1px 浅 hairline(比背景亮一档) |
| `rowLabel` | 深灰 | `#EBEBF0` |
| `sectionHeader` | 次要灰 | `#98989F` |

---

## 2. 材质(Liquid Glass 渐进增强)✅

| 部署版本 | 做法 |
|---|---|
| macOS 14–25 | `.regularMaterial` / `.ultraThinMaterial` |
| macOS 26+ | `if #available(macOS 26, *)` → `.glassEffect()` |

用统一封装 `GlassBackground` 视图隔离版本分支,调用处不感知。

用法约定:

- **HUD / 录音条 / 设置侧边栏**:玻璃材质。
- **设置内容卡片**:近不透明(`.thickMaterial` 或纯色),保证文字清晰,**不用玻璃**。

---

## 3. 字体 ✅(全系统字体,不引第三方)

| 场景 | 字体 | SwiftUI |
|---|---|---|
| 设置页 section header | SF Pro Display | `.font(.headline)` 等 |
| 设置页正文 / 控件 | SF Pro Text | 系统默认 |
| HUD / 录音条 / 品牌感 | SF Pro Rounded | `.font(.system(.body, design: .rounded))` |
| 时长 / 数字 / 波形旁 | SF Mono | `.font(.system(.body, design: .monospaced))` |

字号 🟡:先用系统语义字号(`.headline` / `.body` / `.caption`),实现后按效果图微调。

---

## 4. 形状与间距

| token | 值 | 状态 |
|---|---|---|
| 圆角 — HUD | 16 | ✅ |
| 圆角 — 卡片 | 12 | ✅ |
| 圆角 — 行 / 控件 | 8 | ✅ |
| 圆角 — 录音条 | 全圆(胶囊) | ✅ |
| 设置卡片内边距 | ~16 | 🟡 |
| 设置行高 | ~44(系统标准) | ✅ 系统给 |
| 设置卡间距 | ~20 | 🟡 |

间距优先用 SwiftUI 语义布局(`Form` / `GroupBox` / `.padding()`),数值仅作目标参照,不强标。

---

## 5. 自定义组件尺寸(系统没有的,必须我们定)

这是少数需要明确数值的地方。🟡 表示先用此值,实现后校准。

### 录音条(折叠态 / 极简浮层)

| 项 | 值 | 状态 |
|---|---|---|
| 胶囊宽 × 高 | ~200 × 44 pt | 🟡 |
| 状态圆点直径 | ~8 pt | 🟡 |
| 圆点辉光 | 状态色,柔和外发光 | 🟡 |
| 波形条根数 | ⬜ 待补充 | ⬜ |
| 波形条宽 / 间距 | ⬜ 待补充 | ⬜ |
| 波形最大高度 | ⬜ 待补充 | ⬜ |
| 波形动画帧率 | ⬜ 待补充(建议跟音频电平) | ⬜ |

### Leader HUD(展开态)

| 项 | 值 | 状态 |
|---|---|---|
| 面板宽 | ~360 pt | ✅ |
| action 行高 | ⬜ 待补充 | ⬜ |
| keycap 徽章尺寸 | ⬜ 待补充 | ⬜ |
| 折叠→展开动画 | 🟡 建议 `matchedGeometryEffect` morph | 🟡 |
| 倒计时进度条高度 | ⬜ 待补充 | ⬜ |

### 菜单栏 icon

| 项 | 值 | 状态 |
|---|---|---|
| 形态 | ⬜ 待定(占位 `mic.fill`) | ⬜ |
| 状态表达 | 🟡 变色为主,listening 可加动画 | 🟡 |

---

## 6. 组件映射表(界面元素 → SwiftUI 原生控件)

开发时照这个查,不用猜该用哪个控件。

### 设置页

| 界面元素 | SwiftUI 控件 |
|---|---|
| 左侧 tab 导航 | `NavigationSplitView` / `List` + `.listStyle(.sidebar)` |
| 分组卡片 | `GroupBox` 或 `Form` 的 `Section` |
| section header | `Section { } header: { Text }` |
| 主题三档(默认蓝/跟随系统/自定义) | `Picker(...).pickerStyle(.segmented)` |
| 主题色卡选择 | 自定义 `HStack` of 圆形色块(非系统,见 §5 思路) |
| 开机自启 / 各种开关 | `Toggle` |
| 引擎/模型/语言下拉 | `Picker(...).pickerStyle(.menu)` |
| Base URL 文本框 | `TextField` |
| API Key | `SecureField` + `Button("测试")` |
| 语速等滑块 | `Slider` |
| 状态徽章(✓ 已加载) | 自定义胶囊 `Label` + 状态色背景 |
| 模型下载进度 | `ProgressView(value:)` |
| Reset / 普通按钮 | `Button`(`.bordered` / `.borderedProminent`) |

### HUD / 录音条

| 界面元素 | SwiftUI |
|---|---|
| 浮窗承载 | `NSPanel`(`.nonactivatingPanel`,floating)+ `NSHostingView` |
| 玻璃背景 | `GlassBackground`(封装 material / glassEffect) |
| 波形 | `Canvas`(高频重绘),量大再换 `MTKView` |
| action 列表 | `VStack` of 自定义行 |
| keycap 徽章 | 自定义 `RoundedRectangle` + `Text` |
| 倒计时进度条 | `ProgressView` 或自定义 `Capsule` 动画 |

### 全局快捷键

| 能力 | 方案 |
|---|---|
| 注册全局热键 | `KeyboardShortcuts` 库(已在依赖) |
| 焦点注入 / 读 selected_text / focused_app | AppKit + ApplicationServices(`AXUIElement` / `CGEvent`),无 UI |

---

## 7. 主题系统 ✅(General tab 设置)

| 模式 | 行为 |
|---|---|
| 默认(品牌蓝) | 锁定 `#2B8CFF`,与系统无关。**出厂默认** |
| 跟随系统 | 读 `NSColor.controlAccentColor` |
| 自定义 | `ColorPicker` 任意选 |

主题色只影响**强调色 + listening 状态**,语义色不动。外观(亮/暗)跟随系统,不单独做开关。

实现思路 🟡:用一个 `@AppStorage` 存模式,`EnvironmentValues` 注入当前强调色,各视图读环境而非硬编码。

---

## 8. DesignTokens.swift(代码落地形态)⬜ 待创建

规范的最终形态。建议结构(实现时落):

```swift
enum DS {
    enum Color {
        static let brandBlue = SwiftUI.Color(hex: 0x2B8CFF)
        static let stateThinking = SwiftUI.Color(hex: 0xFFB020)
        static let stateSpeaking = SwiftUI.Color.green   // 系统语义
        static let stateError = SwiftUI.Color.red
        // listening = 当前 accentColor,从环境读
    }
    enum Radius {
        static let hud: CGFloat = 16
        static let card: CGFloat = 12
        static let row: CGFloat = 8
    }
    enum Size {
        static let hudWidth: CGFloat = 360
        static let recordingBarWidth: CGFloat = 200
        static let recordingBarHeight: CGFloat = 44
        // 波形参数待补充
    }
}
```

放在 `Packages/TsutaeCore` 还是 App 层 ⬜ 待定(倾向 App 层,因为是纯 UI;Core 保持无 UI 依赖)。

---

## 待补充清单(汇总 ⬜)

实现/迭代时逐个填回:

- [ ] 波形参数:条数、宽度、间距、最大高度、动画方式
- [ ] HUD action 行高、keycap 尺寸、倒计时条高度
- [ ] 各场景精确字号(现在用系统语义字号占位)
- [ ] 设置卡片内边距 / 卡间距的最终值
- [ ] 菜单栏 icon 正式形态 + 状态动画
- [ ] DesignTokens.swift 放置位置(Core vs App)
- [ ] 一段→二段展开动画的具体形式(见 ui-design.md §B 待验证)
