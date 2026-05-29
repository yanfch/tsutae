# Hotkeys

Global hotkeys + leader-key HUD.

## What goes here

See workspace doc `01-voicebar.md` (Hotkeys: 两段式 leader 模式) and `07-integration.md` (Leader 两段式快捷键).

- `HotkeyManager.swift` — registers global hotkeys via `KeyboardShortcuts` library; handles single-stage actions immediately.
- `LeaderHUD.swift` — SwiftUI overlay window that pops on leader press, shows configured `hud_actions`, accepts second-stage key, dispatches to recipe.
- `HotkeyAction.swift` — enum mapping hotkey → action (recipe name, inline action, or transition to leader mode).
- `RecordingState.swift` — central state machine tracking idle/listening/thinking/speaking; HUD subscribes for live status.

## Constraints

- Leader recording starts immediately on leader press (don't wait for 2nd-stage selection).
- HUD timeout (default 1.5s) → fall back to `default_action`.
- `Esc` cancels leader mode without dispatching.
- Keyboard shortcuts need accessibility permission — handle missing permission gracefully.
