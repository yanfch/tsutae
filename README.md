# tsutae（伝え）

> Voice → any system. Press a hotkey, speak, transcription is POSTed wherever you want.

A voice sidecar for macOS. Configurable hotkey actions, body templating, multi-engine STT/TTS with local + cloud fallback, OpenTelemetry tracing built-in.

## Status

Private alpha. Skeleton only — implementation in progress.

## Stack

- Swift 6 + SwiftUI + macOS 14+
- SwiftPM library (`TsutaeCore`) + Xcode menu-bar App shell
- Hummingbird (HTTP server)
- KeyboardShortcuts (global hotkeys)
- Yams (YAML config)
- swift-argument-parser (headless mode)
- swift-format (Apple official) for formatting; XCTest for tests

## Layout

```
tsutae/
├── App/
│   └── Tsutae/                # Xcode menu-bar app shell (thin)
│       ├── TsutaeApp.swift
│       └── README.md
└── Packages/
    └── TsutaeCore/            # SwiftPM library — all logic lives here
        ├── Package.swift
        └── Sources/TsutaeCore/
            ├── Config/        # Path constants + config.yml loader
            ├── Engines/
            │   ├── STT/       # OpenAI-compatible / WhisperKit / Apple / FluidAudio
            │   ├── TTS/       # Apple / OpenAI / ElevenLabs / Kokoro-MLX
            │   └── VAD/       # Energy / Silero
            ├── Audio/         # Mic capture + playback
            ├── Recipes/       # Recipe loader + body templating + executor
            ├── Hotkeys/       # Global hotkeys + leader HUD
            ├── Secrets/       # Keychain wrapper
            ├── Server/        # Hummingbird HTTP routes
            └── Tracing/       # OTLP file exporter + W3C propagation
```

Each subdirectory carries its own `README.md` describing what to implement and which workspace design doc to follow.

## Implementation order

1. `Config/` — path constants, config loader (mirror kanade's structure)
2. `Audio/` — mic input + speaker output baseline
3. `Engines/STT/OpenAICompatibleSTT.swift` — talk to osaurus first, prove the loop
4. `Engines/TTS/AppleTTS.swift` — `AVSpeechSynthesizer` wrapper
5. `Server/` — Hummingbird app + `/v1/audio/transcriptions` + `/v1/audio/speech`
6. `Hotkeys/` — single-stage hotkeys (ones-shot actions)
7. `Recipes/` — body template + `post_http` action
8. `Hotkeys/LeaderHUD` — second-stage HUD
9. `Tracing/` — FileSpanExporter
10. `Engines` upgrades: WhisperKit, Kokoro, Silero, Notify, etc.

## Getting started

```bash
# Build the SPM package only (no Xcode app yet):
cd Packages/TsutaeCore && swift build && swift test

# When the App shell is ready: open Tsutae.xcworkspace in Xcode.
```

## Design docs

External (workspace-level): `docs/01-voicebar.md`, `docs/04-tracing.md`, `docs/07-integration.md`, `docs/08-recipes.md`, `docs/09-paths.md`. Each subdir's README references the relevant doc by path.

## License

MIT (TBD)
