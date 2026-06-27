# Tsutae

Voice input, speech playback, and local automation for macOS.

Tsutae is a macOS menu-bar app for dictation, local or remote TTS, and localhost API workflows for tools such as Codex, Kanade, Raycast, or custom scripts.

## Interface

<table>
  <tr>
    <td align="center" width="50%">
      <img src="docs/images/standard-light.png" alt="Standard recording capsule in light mode" width="420">
    </td>
    <td align="center" width="50%">
      <img src="docs/images/standard-dark.png" alt="Standard recording capsule in dark mode" width="420">
    </td>
  </tr>
  <tr>
    <td align="center"><sub>Standard recording capsule, light</sub></td>
    <td align="center"><sub>Standard recording capsule, dark</sub></td>
  </tr>
  <tr>
    <td align="center" width="50%">
      <img src="docs/images/minimal-light.png" alt="Minimal recording capsule in light mode" width="220">
    </td>
    <td align="center" width="50%">
      <img src="docs/images/minimal-dark.png" alt="Minimal recording capsule in dark mode" width="220">
    </td>
  </tr>
  <tr>
    <td align="center"><sub>Minimal recording capsule, light</sub></td>
    <td align="center"><sub>Minimal recording capsule, dark</sub></td>
  </tr>
</table>

<table>
  <tr>
    <td width="50%">
      <img src="docs/images/usage.png" alt="Usage dashboard" width="100%">
    </td>
    <td width="50%">
      <img src="docs/images/stt-settings.png" alt="STT settings" width="100%">
    </td>
  </tr>
  <tr>
    <td align="center"><sub>Usage dashboard, light</sub></td>
    <td align="center"><sub>STT settings, dark</sub></td>
  </tr>
</table>

## Features

- Menu-bar app with global hotkey recording.
- Local and remote STT routes.
- Apple TTS, remote OpenAI-compatible TTS, and local FluidAudio Kokoro voices.
- Recording and speaking capsules for lightweight feedback.
- Localhost server for STT, TTS, notifications, app-scoped tokens, and hooks.
- Settings for permissions, models, recipes, secrets, usage, and developer diagnostics.

## Install From Source

Signed and notarized release packages are not published yet. Build Tsutae locally from source.

Requirements: macOS, Xcode, Swift toolchain, and [`just`](https://github.com/casey/just).

```bash
git clone https://github.com/yanfch/tsutae.git
cd tsutae
just build
just restart
```

`just restart` builds the app, copies it to `dist/Tsutae.app`, stops any running Tsutae process, and launches the new build.

First run may ask for Microphone, Speech Recognition, and Accessibility permissions. If macOS blocks the local build, allow it in System Settings > Privacy & Security.

## First Setup

1. Open Tsutae from the menu bar.
2. Open Settings.
3. Choose an STT route: local models or an OpenAI-compatible remote endpoint.
4. Choose a TTS route if you want speech playback.
5. Configure the global hotkey in Settings > General.
6. Optional: enable the local server in Settings > Server and create a client token.

Remote API keys and hook tokens are stored in macOS Keychain. Config files store references or hashes, not secret values.

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

See [Server API](docs/server-api.md).

## Configuration

See [Configuration](docs/configuration.md).

Sandboxed app data:

```text
~/Library/Containers/dev.yanfch.Tsutae/Data/.tsutae/
```

Non-sandbox command-line data:

```text
~/.tsutae/
```

Useful files: `config.yml`, `hotkeys.yml`, `logs/stt-perf.log`, and optional `logs/asr-samples.jsonl`.

## Development

```bash
just build       # build the macOS app
just build-core  # build TsutaeCore
just test-core   # run SwiftPM core tests
just restart     # rebuild and relaunch
just logs        # tail runtime diagnostics
```

## Status

Alpha. Core STT, TTS, settings, and local server flows are usable, but product behavior and APIs may still change.

Planned or incomplete: `/v1/listen`, signed release packages, broader model coverage, and more hardening around local model residency.

## License

[MIT](LICENSE)
