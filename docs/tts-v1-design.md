# Tsutae TTS v1 设计草案

> 状态：草案 v1
>
> 目的：为 Tsutae 下一阶段 TTS 开发收敛产品范围、技术路线与实施顺序。
>
> 参考：
> - `../gui-tui/docs/01-voicebar.md`
> - `../gui-tui/docs/05-dependencies.md`
> - `../gui-tui/docs/07-integration.md`
> - `https://github.com/badlogic/pibot`
> - 当前工程中的 `Packages/TsutaeCore/Sources/TsutaeCore/Config/Config.swift`
> - 当前工程中的 `Packages/TsutaeCore/Sources/TsutaeCore/Server/HTTPServer.swift`

---

## 1. 一句话定义

**Tsutae TTS v1 = 本地播报优先的语音输出 sidecar。**

它不只是“把一段文字念出来”，而是：

- Tsutae 自己能播
- 本地 server 能提供播报接口
- kanade / workflow / agent / shell / webhook 都能调用
- 后续可继续扩展成 API 音频合成与高质量本地 TTS

---

## 2. 这阶段要解决什么

### P0 目标

1. **把 Tsutae 变成一个可靠的本地播报器**
2. **提供可调用的 TTS server 接口**
3. **优先服务 agent / workflow 通知播报场景**
4. **用最稳的引擎先打通完整闭环**
5. **为本地高质量 TTS 与 remote TTS 留好结构**

### 成功标准

- 外部可通过 `POST /v1/speak` 让这台 Mac 说话
- 可通过 `POST /v1/stop` 停止当前播报
- 设置页中的 TTS 不再只是 prototype，而是真配置
- 能配置基础播放策略：voice / rate / interrupt / queue
- 本地播放状态可被 app / server 共同观察

---

## 3. 这阶段不做什么

### 明确不做

1. 完整 conversational voice loop
2. 一上来就做本地大模型 TTS 默认主线
3. 长文本阅读器级别的复杂播放控制
4. 一开始就做 streaming TTS UI 体验
5. 一开始就做多 provider 复杂路由策略
6. 一开始就做 voice cloning
7. 一开始就做 `/v1/audio/speech` 作为主线能力

### 原因

TTS 如果一开始把“本地模型、远程 provider、流式音频返回、音色库、复杂 fallback、UI 展现”一起上，会非常容易像早期 STT 一样进入抽象过重、路径不稳、热路径难控的状态。

---

## 4. 应用场景发散

## 4.1 P0 场景：agent / workflow 通知播报

这是当前最确定的主场景。

### 例子

- “kanade 已完成日报整理。”
- “测试已通过，可以开始提交。”
- “部署失败，需要检查生产环境变量。”
- “本轮转写已复制到剪贴板。”

### 特征

- 短句
- 低延迟优先于高音质
- 需要 stop / interrupt
- 适合直接本地播，不要求返回音频文件

### 对应能力

- `POST /v1/speak`
- `POST /v1/stop`

---

## 4.2 P0 场景：本地系统播报 sidecar

让 Tsutae 成为全系统都能调用的“语音输出总线”。

### 例子

- shell 脚本完成后播报
- Shortcuts / webhook 触发播报
- 其他本地工具不再各自集成 TTS

### 例子接口

```bash
curl -X POST http://127.0.0.1:1338/v1/speak \
  -H "Content-Type: application/json" \
  -d '{"text":"构建完成"}'
```

---

## 4.3 P1 场景：朗读最近结果 / 选中文本 / 剪贴板

### 例子

- 朗读最近一次转写结果
- 朗读剪贴板
- 朗读 agent 生成的最终摘要

### 判断

有价值，但不是 v1 核心主线。v1 可以只保留轻入口，不做完整阅读器。

---

## 4.4 P2 场景：OpenAI 兼容音频合成

### 目标

提供 `POST /v1/audio/speech`，返回音频数据给调用方自己处理。

### 判断

重要，但不应先于 `/v1/speak`。

---

## 5. 场景收敛结论

### v1 主线

优先解决这两个：

1. **通知播报**
2. **本地 sidecar 播报接口**

### v1 次级能力

- 试听 preview
- 停止播报
- 朗读短文本（作为轻入口）

### v2 以后再做

- 音频文件合成 API
- 高质量本地模型默认化
- 流式输入 / 流式音频输出
- 语音对话闭环

---

## 6. 技术路线结论

## 6.1 总体路线

长期方向采用：

- **FluidAudio local TTS**
- **Remote TTS**
- **Apple TTS fallback**

但开发顺序不一步到位。

---

## 6.2 v1 默认主线

### 先用 Apple TTS 打通

v1 默认引擎建议：

- **Primary default: AppleTTS**

原因：

1. 零模型下载
2. 零预热门槛
3. 零隐藏热路径 surprise
4. 最适合先做通知播报
5. 最容易先把 server / queue / interrupt / state 跑稳

---

## 6.3 FluidAudio 在 TTS 里的角色

### 结论

**TTS 也应该接入 FluidAudio。**

但建议作为 **v1.5 / v2 的本地高质量路线**，而不是 v1 默认路径。

### 原因

FluidAudio 当前已具备 TTS 能力，适合 Tsutae 后续接入：

- Swift / CoreML / Apple 平台原生
- 本地优先路线与 Tsutae 一致
- 模型能力统一在同一生态内
- 后续可与 STT 的模型管理、预热、缓存思路共用

### 模型策略

**优先使用 FluidAudio 官方支持的 TTS backend / 模型，不先自己扩散选型。**

原因：

- 集成成本最低
- 模型生命周期更可控
- 推理链路更稳
- 后续调优更有文档与上游参考

---

## 6.4 Remote 在 TTS 里的角色

Remote TTS 应保留，但不作为 v1 首要交付。

适合后续接入：

- `OpenAICompatibleTTS`
- 更高质量商用 provider（如未来单独扩展）

### 使用场景

- 需要更自然音色
- 需要统一外部音频合成协议
- 需要将 Tsutae 暴露为 OpenAI 兼容 `/v1/audio/speech`

---

## 6.5 Apple fallback 的语义

TTS 的 fallback 语义 **不能完全照搬 STT**。

### STT 的 fallback

目标是“无论如何尽量拿到文本”。

### TTS 的 fallback

目标分两类：

1. **通知播报**：只要能发声即可，fallback 合理
2. **指定音色 / 指定 provider / 指定音频格式**：fallback 不能乱切

### 收敛

- 对 **`/v1/speak` 播放路由**：默认可以 fallback 到 AppleTTS
- 对 **`/v1/audio/speech` 音频合成路由**：默认不做 silent fallback，失败应显式返回错误

---

## 7. v1 能力边界

## 7.1 先做的 API

### `POST /v1/speak`

作用：本地直接播报。

建议请求体：

```json
{
  "text": "构建完成",
  "voice": "default",
  "rate": 1.0,
  "interrupt": true,
  "source": "kanade"
}
```

建议返回：

```json
{
  "ok": true,
  "state": "queued"
}
```

### `POST /v1/stop`

作用：停止当前播报。

v1 可以先做成“全局 stop”，后续再加按 `source` 细分。

---

## 7.2 v1 建议一起做的状态接口

### `GET /v1/state`

虽然不是你刚才点名的第一优先，但建议尽早补上，方便 app / server / 外部工具统一观察。

建议结构：

```json
{
  "state": "idle",
  "speaking": false,
  "queueLength": 0,
  "currentSource": null
}
```

---

## 7.3 后续再做的 API

### `POST /v1/audio/speech`

作用：按 OpenAI 兼容形态返回音频，而不是直接本地播出。

这个能力应放到后续阶段，因为它带来：

- 输出格式问题
- route 选择问题
- remote provider 问题
- 更严格的失败语义

---

## 8. v1 运行时设计

## 8.1 核心运行时对象

建议新增一个统一的 **TTS Playback Coordinator / Service**，负责：

- 当前 speaking state
- request queue
- interrupt policy
- stop
- source 跟踪
- engine 选择与 fallback

不要把这些逻辑散在 UI、HTTP route、引擎实现里。

---

## 8.2 v1 状态机

建议最小状态：

- `idle`
- `speaking`
- `stopping`
- `error`（可只做瞬时错误，不长期占状态）

### 队列相关

- 当前正在播报 0 或 1 条
- 后面有若干 queued items
- 若 `interrupt = true`，新请求可打断当前播放

---

## 8.3 v1 播放策略

建议先支持两种：

- `interruptCurrent`
- `queueAfterCurrent`

默认策略建议：

- 外部通知类请求：`interruptCurrent = true`
- preview / 手动试听：也可默认打断

后续如果真有需要，再扩展来源优先级与去重。

---

## 9. 配置结构建议

当前 `Config.TTSConfig` 已有雏形，但带有较强 prototype 痕迹：

- `premiumEngine`
- `premiumVoice`
- `premiumForSpeak`
- `premiumForAPI`

这些字段表达了“不同用途走不同引擎”的方向，但不够稳定。

---

## 9.1 建议的结构演进方向

把 TTS 拆成两个语义层：

### A. Playback Route

用于本地播报：

- primary engine
- fallback engine
- default voice
- rate
- interrupt policy
- queue policy
- output device（后续）

### B. API Synthesis Route

用于输出音频：

- engine
- voice
- model
- format
- remote config / secret ref

---

## 9.2 v1 可接受的折中

为了避免一次性重构太大，v1 可以先沿用现有 `TTSConfig` 落地 AppleTTS + playback 逻辑，
但代码层要按“playback route”去组织，不要再继续加重 `premiumForSpeak / premiumForAPI` 这种语义。

换句话说：

- **配置兼容可保留**
- **实现分层要先收正**

---

## 10. Settings 信息架构建议

当前 TTS 页还是 prototype。

v1 建议让它变成真正可配置，但仍保持克制。

## 10.1 第一版结构

### Voice Engine

- Engine
- Voice
- Rate
- Output（先可只显示 System）

### Playback

- Interrupt current speech
- Queue policy
- Optional fallback indicator

### Preview

- 小段文本输入
- Preview 按钮
- Stop 按钮

### Integration

- Server exposure status
- `/v1/speak`
- `/v1/stop`
- 后续 `/v1/audio/speech` 先只标 planned

---

## 10.2 v1 不建议提前暴露的内容

- 多 provider 大矩阵
- 复杂 premium routing
- voice cloning
- 本地模型库管理（如果 local TTS 还没接入）

---

## 11. 接入 FluidAudio local TTS 的纪律

等 TTS 进入本地模型阶段时，必须沿用 STT 已经总结出来的纪律。

### 必须遵守

1. **不能在热路径偷偷下载模型**
2. **模型下载必须显式管理**
3. **必须有 ready / warming / downloaded 状态**
4. **必须有 runtime cache**
5. **必须支持 prewarm**
6. **不能 silent fallback 到别的本地模型**
7. **首次 warm / load 需要可视化与 gate**

这部分不要因为是 TTS 就重走 STT 的弯路。

---

## 12. 里程碑建议

## Milestone 1：本地播报器成型

### 范围

- AppleTTS engine
- `/v1/speak`
- `/v1/stop`
- speaking state
- TTS settings 真接线
- preview

### 目标

让 Tsutae 先成为一个稳定、可调用的本地播报 sidecar。

---

## Milestone 2：播放体验与运行时完善

### 范围

- queue / interrupt policy
- `GET /v1/state`
- source 跟踪
- 轻量错误反馈
- app 内 speaking 观测

---

## Milestone 3：local / remote 结构扩展

### 范围

- FluidAudio local TTS 接入
- local 模型状态管理
- prewarm / cache / gate
- remote TTS 接入

---

## Milestone 4：API synthesis

### 范围

- `/v1/audio/speech`
- 输出格式与 provider 选择
- 更严格的 route / error 语义

---

## 13. 当前拍板结论

### 已收敛的决定

1. **下一项大功能做 TTS**
2. **先写设计，再开发**
3. **技术总方向采用：FluidAudio local + remote + Apple fallback**
4. **但 v1 默认主线先用 AppleTTS**
5. **先做 `/v1/speak` 与 `/v1/stop`**
6. **优先服务 kanade / workflow / 本地 sidecar 通知播报**
7. **FluidAudio 模型优先用官方已支持的那套，不先自行发散**

---

## 14. 下一讨论主题

在技术路线基本确定后，下一步需要单独讨论：

**TTS 播报时，用户侧应该看到什么展现形式？**

候选方向包括：

- 说话中的语音胶囊
- companion / 小型播报提示
- 纯系统通知
- 菜单栏状态变化
- 完全静默，只听得到声音

这个问题会直接影响：

- speaking state 如何在 UI 中表达
- 是否需要复用现有 recording capsule
- `/v1/speak` 被外部触发时，是否要打扰用户视觉注意力
- stop / interrupt 是否需要显式入口

这个问题单独讨论，不与本草案混在一起拍板。
