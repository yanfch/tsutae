# tsutae

Voice input, speech playback, and local automation for macOS.

Tsutae is a macOS menu-bar app for turning speech into text, speaking text back through local or remote TTS, and exposing a localhost API for tools such as Codex, Kanade, Raycast, or custom workflows.

## Status

Alpha. The core STT, TTS, settings, and local server flows are usable, but the product and API are still changing.

Current focus:

- Speech to Text with local and remote routes.
- Text to Speech with Apple TTS, remote OpenAI-compatible APIs, and local FluidAudio Kokoro voices.
- A localhost server for STT, TTS, notifications, app-scoped tokens, and per-client hooks.
- macOS companion capsules for recording, warmup, errors, and speaking state.

Planned or incomplete:

- `/v1/listen` live-listening control.
- More complete public docs and release packaging.
- Broader model coverage and more production hardening around local model residency.

## App

- Menu-bar app with a settings window.
- Global hotkey recording flow.
- Recording capsule with standard/minimal presentation.
- TTS speaking capsule shared by local playback and server-triggered speech.
- Settings for STT, TTS, server clients, permissions, developer probes, recipes, secrets, and hotkeys.

## Local Server

Default bind: `http://127.0.0.1:1338`

Main endpoints:

- `GET /health`
- `GET /v1/state`
- `GET /v1/models`
- `GET /v1/tts/voices`
- `POST /v1/audio/transcriptions`
- `POST /v1/audio/speech`
- `POST /v1/speak`
- `POST /v1/notify`
- `POST /v1/stop`

Token auth can be enabled in Settings > Server. Tokens are issued per client and can be scoped to specific APIs. See [Server API](docs/server-api.md) for parameters and examples.

## Development

Common commands are in `justfile`:

```bash
just build
just test-core
just restart
```

Useful commands:

- `just build` builds the macOS app.
- `just test-core` runs the SwiftPM core tests.
- `just restart` rebuilds and relaunches the development app.
- `just logs` tails Tsutae logs.

## Layout

```text
tsutae/
├── App/
│   └── Tsutae/
│       ├── Tsutae.xcodeproj
│       └── Tsutae/
│           ├── TsutaeApp.swift
│           ├── Views/
│           ├── Assets.xcassets/
│           └── zh-Hans.lproj/
├── Packages/
│   └── TsutaeCore/
│       ├── Package.swift
│       └── Sources/TsutaeCore/
│           ├── Audio/
│           ├── Config/
│           ├── Core/
│           ├── Engines/
│           ├── Server/
│           ├── STT/
│           └── TTS/
└── docs/
    ├── server-api.md
    ├── ui-design.md
    └── design/
```

## Feedback

Open issues or product feedback on [GitHub](https://github.com/yanfch/tsutae/issues).

## License

MIT
