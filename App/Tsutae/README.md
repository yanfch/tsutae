# Tsutae App (macOS menu-bar)

Thin SwiftUI app shell that hosts `TsutaeCore`. The heavy lifting all lives in the `TsutaeCore` SPM package next door.

## What goes here

- `TsutaeApp.swift` — `@main` entry. Defines `MenuBarExtra` scene + `Settings` scene.
- `Views/MenuContent.swift` — Menu-bar dropdown content (status indicator, quick actions).
- `Views/SettingsView.swift` — Settings window with tabs: General / STT / TTS / VAD / Hotkeys / Recipes / Secrets / Server / About. See workspace doc `01-voicebar.md` §设置页 for the layout we want.
- `Views/LeaderHUDView.swift` — Floating overlay shown on leader-key press (the second-stage HUD).
- `Resources/` — Assets, icons, localization.

## Build target

This becomes an Xcode project (`Tsutae.xcodeproj`) once we open it the first time. Do **not** generate a project file here yet — let the developer pick the bundle ID / signing on first open.

When generating the Xcode project:

- Bundle ID: `dev.yanfch.tsutae` (placeholder; final TBD)
- Deployment target: macOS 14.0
- Sandbox: **off** (we need global hotkeys, mic, accessibility API, outbound HTTP).
- Hardened runtime: **on**
- Entitlements: `com.apple.security.device.audio-input`, `com.apple.security.network.client`
- LSUIElement: `YES` (background app, no Dock icon)
- Login Item: use `SMAppService.mainApp` API (no third-party).

## Constraints

- This shell stays tiny — anything that can live in `TsutaeCore` should.
- No business logic in views — views call into TsutaeCore actors / managers.
- Settings UI uses SwiftUI's built-in `Settings` scene; no third-party preferences framework.
