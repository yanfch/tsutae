# Config

Path constants + `config.yml` loader. See workspace doc `09-paths.md`.

## What goes here

- `Paths.swift` — TsutaeDir / configFile / recipesDir / modelsDir / tracesDir constants. Honor `TSUTAE_DIR` and `TSUTAE_TRACES_DIR` env vars.
- `Config.swift` — top-level `TsutaeConfig` struct + Yams decoder.
- `EngineConfig.swift` — per-engine config sub-structs (STT/TTS/VAD primary + fallback).

## Conventions

- Default location: `~/.tsutae/config.yml`
- Single file in MVP. Once we need it, split out `hotkeys.yml` / `engines/*.yml` (see workspace doc `09-paths.md`).
- API tokens never live in config — store in Keychain, reference by `api_key_keychain: <name>`.
