# tsutae UI 设计

> 本文档定义 tsutae（VoiceBar）的界面构成、各页面职责、技术选型，以及需要设计师产出的图清单。
> 配套设计文档：`gui-tui/docs/01-voicebar.md`（设置页布局）、`07-integration.md`（leader 两段式快捷键）、`08-recipes.md`（配方）、`09-paths.md`（配置/密钥）。

## 技术选型：SwiftUI 为主，AppKit 桥接

整体用 **SwiftUI**，AppKit 只在系统集成的几个点上包一层。

理由：

- README 已定 Swift 6 + SwiftUI + macOS 14+，App shell 已用 `MenuBarExtra` + `Settings` scene。
- `01-voicebar.md` 明确"SwiftUI 原生"；`03-panel.md` 推荐 SwiftUI 以便未来和 AgentPanel 合体成单 App。
- macOS 14 的 SwiftUI 对菜单栏 App、设置窗口、浮层都够用，不需要整体下沉 AppKit。

需要 AppKit 桥接的点（用 `NSViewRepresentable` / `NSHostingView` / `NSPanel` 包一层）：

| 场景 | 为什么需要 AppKit | 做法 |
|---|---|---|
| Leader HUD 浮窗 | 无边框、不抢焦点、置顶、点外面不消失 | `NSPanel`（`.nonactivatingPanel`，`level = .floating`）内嵌 `NSHostingView(rootView: LeaderHUDView)` |
| 全局快捷键 | SwiftUI 无原生全局热键 | `KeyboardShortcuts` 库（内部走 Carbon/AppKit） |
| 焦点 App 注入文本 / 读 `selected_text` / `focused_app` | Accessibility API、`CGEvent` | 纯 AppKit + ApplicationServices，无 UI |
| 录音波形可视化 | 高频重绘 | 先用 SwiftUI `Canvas`，量大再换 `MTKView` |

心智：**SwiftUI 写所有"页面"，AppKit 只负责"系统级窗口行为和输入注入"**。

## 应用形态

tsutae 是后台菜单栏 App（`LSUIElement = YES`，无 Dock 图标）。UI 表面分三类：常驻入口、浮层、设置窗口。

```
┌─────────────────────────────────────────────────────────┐
│ 菜单栏 🎙️  ← MenuBarExtra（常驻入口）                     │
│   └─ 点击 → 下拉主面板（窗口 A）                          │
│                                                           │
│ ⌥+Space → Leader HUD 浮层（浮层 B，核心交互）             │
│ ⌥+V     → 极简录音条浮层（浮层 D）                        │
│                                                           │
│ Settings → 设置窗口（窗口 C，9 个 tab）                   │
│                                                           │
│ 首次启动 → 权限引导（窗口 E）                             │
└─────────────────────────────────────────────────────────┘
```

合计 **3 个窗口 + 2 个浮层 + 9 个设置子页**。

---

## 窗口 / 浮层清单

### A. 菜单栏下拉面板（MenuBarExtra window）

点菜单栏麦克风图标弹出。`menuBarExtraStyle(.window)`。

内容：

- 顶部：当前状态徽章（idle / listening / thinking / speaking）+ 一个大录音按钮（按住说话 / 点击切换）
- 中部：最近一次转写结果卡片（文本 + 复制 / 重发 / 清除）
- 集成状态行：osaurus / kanade / TraceLocal 的在线小绿点（数据来自周期性 `/health` 探测，见 `07-integration.md` §服务发现）
- 底部：Settings… / Diagnose… / Quit

菜单栏 icon 本身随状态变色/变形：idle 静态、listening 跳动、speaking 声波。

### B. Leader HUD 浮层（核心交互，折叠 / 展开两态）

按 `⌥+Space` 弹出的屏幕中央浮窗。产品灵魂，单独精细设计。

**重要设计决策：默认折叠，按需展开。**

- **折叠态（默认）= 极简录音条**：只有一个状态色圆点 + 会动的波形，**没有任何文案**。波形在动本身就表示在录音，圆点表状态色，足够。80% 场景（直接说 → 注入焦点）只看到这根安静的小条，不被 action 列表打扰。
- **展开态**：按某个键（建议 Tab，或再点一下 leader）才展开出完整 action 列表 + 倒计时。需要选目标系统时才展开。

关键行为（来自 `07-integration.md`）：

- 录音从 leader 按下时**立即开始**，不等用户选 action。
- 倒计时（默认 1.5s）内不按第二段键 → 走 `default_action`。
- 第二段键可在说话过程中按（左手 leader、右手选 action）。
- `Esc` 取消，不派发。
- HUD 内容由配置渲染，不写死。

需要画的状态：

1. **折叠态（默认）**：胶囊条，状态色圆点 + 动态波形，无文案（= 下方 D，两者其实是同一个组件）
2. **展开态**：折叠条向下展开出 action 列表（每行 icon + 按键 + label）+ 底部倒计时进度条
3. **实时转写态**：展开后顶部可选显示 partial 文字（这块文字只在展开态出现）
4. **submenu 态**：进二级菜单（如 `W → Work → N → Notion 项目`）
5. **取消态**：Esc 后的短暂反馈
6. **派发反馈态**：on_success（"已写入 Notion"）/ on_failure（"失败，已存剪贴板"）

#### 交互契约（已锁定，照此实现）

两段式成立，先做这套列表版基础实现，用过之后再优化：

- **两段式**：第一段 = 录音 + 默认目的地；第二段 = 切换目的地。
- **第一段（默认）**：按 leader 直接说完、不按第二段键 → 发到设置里配的 `default_action`（如注入焦点 App，或某个默认配方）。
- **第二段（切换）**：录音中或说完后按第二段键 → 改发到对应目标（如按 `T` 创建任务给 Orchestrator）。
- **倒计时**：不按第二段键，超时（默认 1500ms）走第一段默认。
- **Esc** 取消，不派发。

#### 待验证（实现后再确认，现在别过度设计）

- **一段 → 二段的展示形式**：折叠条怎么展开、用 Tab 还是再按 leader、列表 vs 环形——先用最简单的占位实现，真用过几天再定。
- **第二阶段优化方向**（都依赖列表版作为底座 / 兜底，现在不做）：
  - **意图路由（A）**：本地 LLM 从话里判断目的地，列表降级为纠正用兜底。体验上限高但有猜错风险，需要配方自描述路由规则。
  - **上下文智能默认（C）**：按 `{{cwd}}` / `{{focused_app}}` / 时间动态算最可能的 1-3 个目标，其余进"更多"。
  - **环形手势（B）**：按住 leader + 方向推，radial menu，肌肉记忆，限 6 项以内。

### C. 设置窗口（SwiftUI `Settings` scene）

左侧 Tab 导航，9 个页。布局参照 `01-voicebar.md` §设置页。详见下方"设置页详解"。

### D. 极简录音条浮层（= Leader HUD 折叠态，同一组件）

直接 `⌥+V`（注入焦点）/ `⌥+C`（转剪贴板）时，或 leader 折叠态下，显示的极简胶囊条：**只有状态色圆点 + 动态波形，无文案、无时长、无 action 列表**。波形动 = 在录音，圆点 = 状态色，这两个就够表达全部信息。

这和 Leader HUD 的折叠态是同一个 SwiftUI 组件，leader 场景下按 Tab 可展开成完整 HUD，纯录音场景（⌥+V/⌥+C）则不可展开。

### E. 首次启动 / 权限引导窗口

缺权限时阻塞引导。两步：

1. 麦克风权限（`com.apple.security.device.audio-input`）
2. 辅助功能权限（Accessibility，用于全局快捷键 + 焦点注入）

每步显示当前授权状态、为什么需要、一键打开系统设置对应面板。授权后自动前进。

---

## 设置页视觉规范（已定稿，亮/暗双版已验证）

所有 tab 复用这套骨架，不再逐页调风格。

**布局**：左侧玻璃侧边栏（translucent material，壁纸隐约透出）+ 右侧内容区。侧边栏选中项用强调色 tinted 圆角 pill。

**内容区**：分组白/暗卡片，**卡片不透明**（保证文字清晰，不用玻璃）。

| 元素 | 亮色 | 暗色 |
|---|---|---|
| 内容区背景 | `#F2F2F4` | `#1C1C1E` |
| 卡片 | 白 + 1px hairline + 微阴影 | `#2C2C2E` + 1px 浅 hairline（比背景亮一档）|
| 行 label | 深灰 ~13pt | `#EBEBF0` ~13pt |
| section header | 次要灰 ~11pt | `#98989F` ~11pt |
| 强调色 | `#2B8CFF` | `#2B8CFF`（深色卡上更跳）|

**几何**：卡片圆角 12 / hairline 分隔行 / 行高 ~44px / 行内边距 ~16px / 卡间距 ~20px。

**控件**：一律原生 macOS（segmented control、toggle、popup button 带 chevron、bordered button），不用网页扁平风。label 左对齐、控件右对齐、垂直居中。

**字体**：section header 用 SF Pro Display，行用 SF Pro Text。

**外观**：跟随系统，亮/暗自动切（SwiftUI 自动适配，不单独做开关）。

---

## 设置页详解（9 个 tab）

### 1. General
- 开机自启（`SMAppService.mainApp`）
- 默认 action（不按第二段键时）
- 界面语言、转写默认语言
- Reset to defaults

### 2. STT
- 主引擎下拉（WhisperKit / FluidAudio / AppleSpeech / OpenAICompatible）
- 模型选择 + 状态（含下载态：未下载 / 下载中带进度 / 已加载带体积 / 损坏可重下）
- 语言（auto / 指定）
- Fallback 引擎 + Base URL + API Key（引用 Keychain）+ Test

### 3. TTS
- 主引擎（AVSpeechSynthesizer / KokoroMLX / OpenAICompatible / ElevenLabs）
- 音色、语速、Preview
- Premium 引擎 + 应用范围（`/speak` / `/v1/audio/speech`）

### 4. VAD & Behavior
- VAD 引擎（Silero / Energy）+ 灵敏度
- 停顿时长（pause_duration_ms）
- Allow barge-in、Echo cancel 开关

### 5. Hotkeys（最复杂）
- 一段式快捷键列表（key → action）
- Leader 配置：leader 键、default_action、hud_timeout_ms
- HUD actions 可视化编辑器：每行 key / icon / label / 绑定（recipe 引用 或 inline action）
- submenu 嵌套编辑（一层）
- 字段与交互细节单独拆见下方"附：Hotkeys 编辑器交互"

### 6. Recipes
- 配方列表（来自 `~/.tsutae/recipes/*.yml`）
- Add from template（内置模板：Notion / Obsidian / Linear / Slack / Orchestrator / personal-inbox …）
- 配方详情（只读 YAML 预览，编辑走 `$EDITOR` / 文件系统）
- Test with dummy text 弹窗（不录音，跑一遍看发送结果）

### 7. Secrets
- Keychain 管理表格：Name / 掩码 Value / Used by / Test
- 命名规范 `<app>.<engine>_<purpose>`（见 `09-paths.md`）
- Add / Test，不显示明文

### 8. Server
- 端口（默认 1338）、bind（默认 127.0.0.1）
- 运行状态指示（● Running on http://127.0.0.1:1338）
- auto-start at login

### 9. About
- 版本、许可、链接、Diagnose 入口

---

## 需要产出的设计图清单

每张建议给 **浅色 + 深色** 两版（macOS 要适配 appearance）。已出稿的效果图存档在 `design/mockups/`（见该目录 README）。

### P0 — 核心体验（先画）
1. 极简录音条 / Leader HUD 折叠态（状态色圆点 + 动态波形，无文案）✅ 已出稿
2. Leader HUD — 展开态（折叠条展开出 action 列表 + 倒计时）
3. Leader HUD — submenu 态（二级菜单）
4. Leader HUD — 派发反馈态（success / failure）
5. 菜单栏下拉主面板（状态 + 最近转写 + 集成在线点）

### P1 — 设置核心三页
6. Settings / STT（含模型下载四态：未下载 / 下载中 / 已加载 / 损坏）
7. Settings / Hotkeys（leader + HUD actions 可视化编辑器）
8. Settings / Recipes（列表 + 详情 + Test 弹窗）

### P2 — 其余设置 + 边界态
9. Settings / General（含主题三档：默认蓝 / 跟随系统 / 自定义）
10. Settings 其余 tab 总览（TTS / VAD / Secrets / Server / About，可合成一张多 tab 图）
11. 首次启动权限引导（麦克风 + 辅助功能两步）
12. Diagnose 自检结果页（各引擎 / 权限 / 端口状态）

### 非界面图（帮开发对齐）
13. 状态机图：idle → listening → thinking → speaking → idle，含 barge-in / 打断 / 超时分支（对应 `RecordingState.swift`）
14. Leader 交互时序图：按 leader → 立即录音 → 第二段键 / 倒计时超时 → 转写 → 执行 recipe → on_success/on_failure

---

## Design tokens（已定，统一 14 张图风格）

### 颜色

| token | hex | 用途 |
|---|---|---|
| 品牌主色 / 默认强调色 | `#2B8CFF` 电光蓝 | 主按钮、选中项、默认主题色 |
| 品牌色深变体 | `#1B6FE0` | 渐变底端 / 暗色模式 |
| 状态 — idle | `#8A8A8E`（系统次要灰） | 待机 |
| 状态 — listening | = 当前强调色 | 录音中（默认蓝，跟随主题变色） |
| 状态 — thinking | `#FFB020` 琥珀 | 转写/处理中（固定，不随主题） |
| 状态 — speaking | `#30D158`（systemGreen） | TTS 播放中（固定，不随主题） |
| 状态 — error | `#FF453A`（systemRed） | 失败（固定，不随主题） |

关键规则：**只有 listening 跟随强调色，thinking/speaking/error 是固定语义色**（含义不能被主题色冲掉）。状态色同时驱动菜单栏 icon、HUD 顶部条、录音条圆点/波形，一处定义多处复用。语义色尽量用 Apple 系统色（`systemGreen`/`systemRed`/`systemOrange`），自动适配亮暗模式。

### 材质（Liquid Glass 渐进增强）

Liquid Glass（`.glassEffect()` / `GlassEffectContainer` / `.buttonStyle(.glass)`）是 SwiftUI 原生 API，但只在 **macOS 26 (Tahoe)+** 可用（需 Xcode 26 SDK）。我们基线是 macOS 14，所以分层降级：

| 部署版本 | 做法 |
|---|---|
| macOS 14–25 | `.regularMaterial` / `.ultraThinMaterial`（系统毛玻璃，开销极低） |
| macOS 26+ | `if #available(macOS 26, *)` 内换成 `.glassEffect()`，拿到液态流动/反光/morph |

用同一个 `GlassBackground` 视图封装这个分支，调用处不感知版本。

设置页材质策略（混合，别全玻璃）：外壳/侧边栏用半透明 material 保留玻璃感，**内容卡片用近不透明卡（`.thickMaterial` 或纯色）保证文字清晰**——和 macOS 26 System Settings 自己的做法一致。

### 字体（全部系统字体，不引第三方）

| 场景 | 字体 |
|---|---|
| 正文 / 控件 / 设置页 | SF Pro Text / Display（系统默认） |
| HUD / 录音条 / 品牌感处 | **SF Pro Rounded**（圆润、有亲和力，适合语音工具） |
| 时长 / 数字 / 波形旁 | SF Mono（等宽，跳秒不抖） |

### 形状

| token | 值 | 用途 |
|---|---|---|
| 圆角 | 16（HUD）/ 12（卡片）/ 8（行）/ 全圆（录音条胶囊） | 统一圆角 |
| HUD 宽度 | ~360pt | Leader HUD（展开态）固定宽 |
| 录音条尺寸 | ~200×44pt 胶囊 | 极简录音条（折叠态） |

---

## 主题系统（跟随系统 / 自定义）

`NSColor.controlAccentColor` 可读到用户在系统设置里选的强调色，`Color.accentColor` 自动跟随。提供三档（General tab 里设置）：

| 模式 | 行为 |
|---|---|
| **默认（品牌蓝）** | 锁定 `#2B8CFF`，与系统无关。tsutae 出厂默认 |
| **跟随系统** | 读 `controlAccentColor`，用户选橙就橙、选粉就粉 |
| **自定义** | 颜色选择器任意挑 |

规则同上：主题色只影响**强调色 + listening 状态**（录音波形/圆点、选中态、主按钮），thinking/speaking/error 永远固定语义色。

外观（亮/暗）跟随系统，不单独做开关（SwiftUI 自动适配）。

---

## 附：Hotkeys 编辑器交互（最复杂的一页，先对齐字段）

对应配置文件 `~/.tsutae/hotkeys.yml`（见 `09-paths.md`）。编辑器需覆盖：

一段式快捷键行：
- `key`（录制快捷键控件）
- `action`（下拉：send_to_focused_app / transcribe_to_clipboard / stop_speaking / post_http / open_url …）
- action 为 post_http / open_url 时，展开内联参数（url / method / headers / body）或改为"引用 recipe"

Leader 配置区：
- `leader` 键（录制控件）
- `default_action`（下拉，倒计时结束时执行）
- `hud_timeout_ms`（数字，默认 1500）

HUD actions 列表（可增删拖排序）：
- 每行：`key`（单字符）/ `icon`（emoji 选择）/ `label`（文本）
- 绑定二选一：`recipe`（从 recipes 下拉引用）或 inline `action`
- 可展开为 `submenu`（一层嵌套，里面又是若干 key/label/绑定）

边界态：
- key 冲突检测（同级别两个 action 用了同一个键）
- recipe 引用失效（引用了不存在的配方）提示
- 缺辅助功能权限时，顶部横幅提示去授权

> 角色/workflow 这类"立法"配置走文件系统 + git（见 `03-panel.md` 设计决策）。tsutae 的 hotkeys/recipes 也可手工编辑 YAML，GUI 编辑器是便利层，不是唯一入口。
