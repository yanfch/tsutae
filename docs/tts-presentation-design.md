# Tsutae TTS 展现形式设计草案

> 状态：草案 v1
>
> 目的：讨论并收敛 Tsutae 在 TTS / 播报场景下的用户侧展现形式。
>
> 关联文档：
> - `docs/tts-v1-design.md`
> - `docs/ui-design.md`

---

## 1. 设计问题

Tsutae 的 TTS 不是单一场景：

1. 外部 agent / workflow 调 `POST /v1/speak` 做短句通知播报
2. 用户在设置页点击 Preview 主动试听
3. 未来可能有“朗读最新结果 / 朗读剪贴板 / 长文本朗读”
4. 未来还可能有“先提醒、后播放”的 notify-first 模式

因此，TTS 不适合只用一种 UI 形态覆盖全部情况。

---

## 2. 已收敛原则

### 原则 1

**持续中的 speaking 状态，不应用系统通知作为主舞台。**

系统通知适合提醒与补充入口，不适合承载 ongoing speaking。

### 原则 2

**TTS 应复用 Tsutae 的胶囊语言，但不能直接复用录音胶囊。**

原因：

- 录音胶囊语义是“输入 / listening”
- speaking 胶囊语义应是“输出 / announcing”
- 两者必须一眼区分

### 原则 3

**Speaking UI 应比 Recording UI 更轻。**

多数 TTS 场景是“短句播报”，不是进入一个完整 voice mode。

### 原则 4

**用户主动触发，与外部被动触发，展现强度应不同。**

- 用户主动 Preview：可更直接显示控制
- 外部 `/v1/speak`：默认更轻、更安静

### 原则 5

**默认先服务短句播报，不先为长文本播放器过度设计。**

---

## 3. 参考产品观察

## 3.1 Apple

### Spoken Content / Read & Speak

Apple 的朗读类能力使用轻控制器（controller）而不是通知中心做主舞台，并且支持：

- Automatically
- Never
- Always

这说明 Apple 对“朗读中”状态的处理更接近：

- 小控制器
- 可见但不重
- 不是系统通知主导

### Live Speech

Apple 在 Mac 上为 Live Speech 使用独立小窗 / menu bar 入口，而不是通过通知中心表达正在说话。

### 启发

- speaking 更适合小控制器 / 小浮层 / 菜单栏状态
- 不适合把通知作为主界面

---

## 3.2 ChatGPT Voice

ChatGPT Voice 更像专用 voice mode：

- 明确的 listening / thinking / speaking 状态
- 专用视觉主表面
- 强模式感

### 启发

适合完整对话模式，不适合 Tsutae v1 的“后台播一句”主场景。

---

## 3.3 ElevenReader / 播放器类产品

此类产品适合：

- 长文本朗读
- 语音播放器
- 进度、scrubber、voice picker

### 启发

未来可参考，但不应成为 Tsutae v1 的默认播报形态。

---

## 3.4 Raycast

Raycast 的异步反馈更接近：

- toast
- HUD
- 可附带动作
- 主窗口关闭时降级成 HUD

### 启发

对 Tsutae 的外部播报请求来说，“轻提示 + 动作”是很合理的方向。

---

## 4. 展现层级建议

Tsutae 的 TTS 展现建议分成三层：

### 第一层：Speaking Capsule

主舞台。表达“正在播报”。

### 第二层：Companion Panel

承载详情、动作、来源、播放前提醒。

### 第三层：System Notification

作为 notify-first 或 missed alert 的补充入口，不作为 ongoing speaking 主界面。

---

## 5. v1 主形态：Speaking Capsule

当前方向收敛：

- 视觉主方向采用“**第三张方案**”的 compact speaking chip / companion 组合
- 交互动作与 notify-first 语义吸收“**第一张方案**”中的播放前提醒逻辑
- speaking UI 也应像录音输入一样，提供 **standard + minimal** 两个密度版本

## 5.1 定义

Speaking Capsule 是一个新的 Tsutae 胶囊组件。

它：

- 属于 Tsutae 胶囊家族
- 复用 Tsutae 的安静、克制、纸感方向
- 但语义上与录音胶囊分离

它不是：

- 录音胶囊换一个文案
- 完整播放器
- 系统通知替身

---

## 5.2 设计目标

1. 一眼看出“Tsutae 正在说话”
2. 一眼看出“是谁触发的”
3. 提供最小 stop / dismiss 能力
4. 不挡当前工作
5. 不和录音胶囊混淆

---

## 5.3 视觉语义

### 不建议继续用 waveform

原因：

- waveform 在 Tsutae 里已经和“输入 / listening”强绑定
- speaking 如果继续使用类似输入波形，会让用户混淆“在听”还是“在说”

### 建议改用的 speaking 语义

优先候选：

1. **speaker glyph + subtle pulse**
2. **speaker glyph + 2~3 个短柱动画**
3. **speaker glyph + outward dots**

其中 v1 最推荐：

- **speaker glyph + pulse**
- 或 **speaker glyph + small bars**

目标是表达“向外发声”，而不是“采集声音”。

---

## 5.4 信息层级

### v1 默认展示的信息

从高到低：

1. **状态**：正在播报
2. **来源**：谁触发的
3. **控制**：停止
4. **摘要**：可选的一行短句

### 推荐默认内容

- 左：speaker / pulse
- 中：source
- 右：stop

例如：

- `🔊 kanade    ×`
- `🔊 workflow  ×`
- `🔊 Tsutae    ×`

### 可选扩展

若要展示更多，可在 expanded / companion 层显示：

- 短摘要文本
- 完整句子
- 来源说明
- 行为按钮

不建议把太长的播报内容直接塞进胶囊本体。

---

## 5.5 密度版本：standard + minimal

### Standard speaking chip（正常版）

适合：

- 大多数 autoplay 播报
- 用户第一次接触 speaking UI
- 需要明确展示来源时
- settings preview / 手动朗读

默认内容：

- speaker icon / pulse
- source
- stop

例如：

- `🔊 kanade    ×`
- `🔊 workflow  ×`

这对应当前更接近第三张图的主形态。

### Minimal speaking chip（极简版）

适合：

- 高频、短句、低打扰播报
- 用户已经熟悉 Tsutae speaking 语义后
- 只需要知道“正在播”，不需要每次看来源文字

默认内容建议：

- speaker icon / pulse
- stop
- 可选非常弱的 source 线索（如颜色点 / tiny tag / hover 才显示）

例如：

- `🔊  ·  ⏹`
- 或 `🔊  kanade-dot  ⏹`

### 设计约束

- minimal 不是把 standard 机械缩短
- minimal 要保留“可停止”能力
- minimal 仍然要与录音极简胶囊清楚区分
- minimal 依然不用 waveform

## 5.6 展开态与 companion

### 默认原则

- chip 本体负责状态与最小控制
- 详情尽量交给 companion

### Companion / expanded 层（可选）

通过 hover / click / 自动触发打开：

- 短摘要
- Stop
- Play later
- Dismiss / Ignore
- Mute Source（未来）
- Open Tsutae（未来）

v1 不要求 speaking capsule 自己做复杂展开结构，可先把展开信息放到 companion。

---

## 6. Companion 的角色

Companion 逻辑可以复用，但语义改为 **announcement / speaking**，不是 error / warning。

## 6.1 Capsule 与 Companion 的分工

### Capsule 负责

- 正在播报
- 来源是谁
- 立刻停止

### Companion 负责

- 播报的短摘要
- 更完整的说明
- notify-first 时的播放前确认
- 未来的“静音此来源 / 打开主界面”等动作

---

## 6.2 两种 companion 模式

### 模式 A：autoplay companion

已经开始播：

- capsule 出现
- companion 可选显示摘要
- 提供 `Stop`

### 模式 B：notify-first companion

还未播放：

- companion 或通知先出现
- 提供：
  - `播放`
  - `忽略`
- 点播放后才真正出现 speaking capsule

---

## 7. System Notification 的角色

## 7.1 适合做什么

1. **notify-first 入口**
2. **用户错过时的补充提醒**
3. **某些低频 agent 结果提醒**

### 建议动作

- `播放`
- `忽略`
- `打开 Tsutae`

---

## 7.2 不适合做什么

1. ongoing speaking 的主界面
2. stop 当前播放的唯一入口
3. 高频播报的主反馈方式

---

## 8. 位置策略建议

## 8.1 v1 推荐默认位置

**Active screen 的 bottom-center（底部中间）**

并与 Dock 保持安全距离。

### 原因

1. 不和系统通知右上角冲突
2. 不和录音胶囊顶部语义冲突
3. 更像“播放控制 / HUD”
4. 可见但不挡当前文档主体

---

## 8.2 不推荐的默认位置

### Top-center

问题：

- 太容易让人联想到录音胶囊
- 容易混淆“输入模式”和“输出模式”

### Right-top

问题：

- 会和系统通知重叠
- 更像 toast / alert，而不是 speaking 状态

---

## 8.3 与多屏的关系

建议 speaking capsule 跟随：

- 当前 active screen
- 或当前鼠标所在 screen

并和 recording bar 的位置持久化逻辑分开，不共用同一位置存储。

---

## 9. 交互流建议

## 9.1 Flow A：autoplay（默认）

1. 外部发送 `/v1/speak`
2. Tsutae 立即开始播报
3. bottom-center 出现 speaking chip
   - 默认可先用 standard
   - 后续可支持切到 minimal
4. 菜单栏 icon 进入 speaking 状态
5. 用户可点击 stop
6. 播报结束后 chip 自动消失

---

## 9.2 Flow B：notify-first

1. 外部发送通知型请求
2. Tsutae 先不播放
3. 显示系统通知或轻 companion
4. 用户点击 `播放`
5. 真正开始播报
6. speaking chip 出现
   - 可直接进入 standard
   - 若用户偏好低打扰，也可用 minimal
7. 播报结束后自动消失

---

## 9.3 Flow C：settings preview

1. 用户在设置页点击 Preview
2. 页内按钮切成 `Stop`
3. speaking capsule 同时出现
4. 保持全局 speaking 状态统一
5. 停止或结束后恢复

---

## 10. v1 组件建议

### 新组件

- `SpeakingCapsuleView`
- `SpeakingCompanionView`（可选复用现有 companion 基础设施）

### 新状态

- `idle`
- `speaking`
- `stopping`

### 新展示信息

- source
- optional summary
- stop action

---

## 11. v1 推荐方案（当前最优先）

### 主方案

**Speaking Chip Family + Companion + Menu Bar 状态**

#### 具体建议

- 主形态：新的 speaking chip family
- 密度：`standard` + `minimal`
- 位置：bottom-center
- standard 内容：speaker pulse + source + stop
- minimal 内容：speaker pulse + stop（可选极弱 source 线索）
- companion：摘要与动作
- 菜单栏：speaking 状态联动
- 系统通知：仅作 notify-first / missed alert

---

## 12. 不建议的 v1 方向

1. 直接复用完整录音胶囊
2. 继续用 waveform 做 speaking 主语义
3. 用系统通知承担 speaking 主舞台
4. 一开始就上独立播放器
5. 一开始就支持长文本完整播放控件

---

## 13. 设计出图方向

建议先出三组效果图对比：

### 方案 A：Quiet Speaker Chip

- 更接近 minimal speaking chip
- 只有 icon / pulse / stop（source 极弱或 hover 再显示）
- 最安静

### 方案 B：Capsule-Family Speaking Bar

- 更接近 standard speaking chip
- 更像 Tsutae 胶囊家族
- 但与录音胶囊清晰区分
- 可带更强品牌感

### 方案 C：Companion-First Announcement

- chip 更轻
- 详情主要靠 companion 承载
- 适合 notify-first 与 agent 摘要提醒
- 可以作为 standard / minimal 共同搭配的详情层

---

## 14. 设计图生成 Prompt 草案

以下 prompt 用于生成方向图，不是最终像素级规范。建议把现有录音胶囊截图一起喂给模型做风格参考。

---

### Prompt A：Quiet Speaker Chip

```text
Design a macOS floating speaking capsule for Tsutae, a quiet menu bar voice sidecar app.

Style reference:
- Keep the same overall product language as the existing Tsutae recording capsule: calm, paper-like, low-saturation, refined, compact, native-to-macOS feeling.
- However, this is NOT a recording UI. It must feel clearly different from listening / recording.
- Do not use an input waveform. Avoid anything that looks like microphone capture.

Visual goals:
- A small bottom-center floating capsule for “currently speaking”.
- Very lightweight, minimal, non-intrusive.
- Speaker/output semantics, not input semantics.
- Show a subtle speaker icon with soft pulse or 2-3 tiny animated bars.
- Show source label, such as “kanade” or “workflow”.
- Show a small stop button on the right.
- Optional very short subtitle line, but keep the default design compact.

Layout:
- Horizontal capsule, rounded, elegant, compact.
- Bottom-center placement on macOS desktop, above the Dock.
- No big shadows, no glassy neon effect, no iOS-style giant blur.
- Native macOS utility aesthetic.

Color direction:
- Quiet neutral surface, like warm paper / muted dark paper.
- One restrained accent for active speaking state.
- Not too colorful.

Need 3 variations:
1. Light mode compact chip
2. Dark mode compact chip
3. Compact chip with short companion panel expanded above it
```

---

### Prompt B：Capsule-Family Speaking Bar

```text
Design a Tsutae “speaking capsule” for macOS, derived from the same family as an existing recording capsule UI, but clearly separated in meaning.

Important constraints:
- It should belong to the same product family as the recording capsule.
- But it must NOT feel like a reused recording bar with changed text.
- No microphone icon, no recording waveform, no listening semantics.
- This is output / announcement / speaking.

Desired UI:
- Floating capsule, bottom-center on screen.
- Primary elements: speaker symbol, subtle active speaking motion, source tag, stop control.
- Optional compact status text like “Speaking” or source-only mode.
- Calm, quiet, native macOS sidecar aesthetic.
- Refined spacing and optical balance.

Visual distinction from recording bar:
- Recording bar = input, waveform, listen/think states.
- Speaking bar = output, speaker pulse, announcement state.
- Use different motion language from recording.

Please create:
1. compact speaking capsule
2. speaking capsule with short message preview
3. speaking capsule with hover/expanded details state

Style keywords:
minimal, elegant, quiet, low saturation, paper and ink, macOS utility, understated premium
```

---

### Prompt C：Companion-First Announcement

```text
Design a macOS TTS announcement UI for Tsutae.

Concept:
- The main speaking state is represented by a very small floating speaker capsule.
- Details are shown in a companion panel above it.
- This is used for agent/workflow voice announcements, not for voice chat.

Need to show:
- Small bottom-center speaking capsule with speaker icon and stop button.
- Companion panel above it with:
  - source name (kanade / workflow / Tsutae)
  - short spoken summary text
  - actions such as Stop / Dismiss / Play later

Important:
- This is not an error panel.
- This is not a system notification mock.
- This is a quiet, product-native announcement surface.
- It should feel calm and trustworthy, not flashy.

Do both light and dark mode.
Also show one variation for “notify first, not yet playing”, where the companion offers Play and Ignore instead of Stop.
```

---

## 15. 下一步

建议下一步做两件事：

1. 先根据上述 prompt 出 2~3 组方向图
2. 再结合图稿继续收敛：
   - speaking capsule 的内容层级
   - 是否显示摘要
   - companion 默认是否出现
   - notify-first 是否进入 v1
