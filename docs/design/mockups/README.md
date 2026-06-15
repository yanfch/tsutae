# 设计稿留存（mockups）

本目录存放 tsutae UI 的效果图（AI 生成的探索稿 + 定稿）。配套规范见 `../ui-design.md`。

> 说明：这些是**视觉方向探索图**，不是像素级交付稿。真实控件以 SwiftUI 原生为准（见 `ui-design.md` §设置页视觉规范）。

## 录音条 / Leader HUD

| 文件 | 说明 | 状态 |
|---|---|---|
| `recording-bar-collapsed-v1.png` | 极简录音条（折叠态）：状态色圆点 + 动态波形 | 探索 |
| `recording-bar-collapsed-minimal.png` | 更精简的录音条变体 | 探索 |
| `leader-hud-expanded-v1-darktone.png` | Leader HUD 展开态（顶部录音 + action 列表 + 倒计时）首版定调图 | 定调参考 |

## 设置页

| 文件 | 说明 | 状态 |
|---|---|---|
| `settings-general-v1.png` | 设置页 General 首版（内容区偏空） | 迭代过程 |
| `settings-general-v2.png` | 第二版（外壳/边框满意，内容区待强化） | 迭代过程 |
| `settings-general-light-final.png` | **亮色定稿**：玻璃侧栏 + 白色不透明卡片 + 原生控件 + 主题三档 | ✅ 定稿 |
| `settings-general-dark-final.png` | **暗色定稿**：背景 `#1C1C1E` / 卡片 `#2C2C2E` / 电光蓝强调 | ✅ 定稿 |

## 已确认的视觉规范（详见 ui-design.md）

- 品牌主色 / 默认强调色：`#2B8CFF` 电光蓝
- 材质：macOS 14–25 用 `.regularMaterial`，macOS 26+ 渐进增强到 `.glassEffect()`
- 字体：设置页 SF Pro Display/Text；HUD/录音条 SF Pro Rounded；数字 SF Mono
- 主题三档：默认蓝 / 跟随系统（读 `controlAccentColor`）/ 自定义
- 设置页骨架：玻璃侧栏 + 不透明分组卡片，亮/暗双版已验证
