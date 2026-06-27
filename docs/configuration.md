# Configuration

Tsutae stores app configuration under `.tsutae` in the process home directory.

For the sandboxed macOS app, that resolves to:

```text
~/Library/Containers/dev.yanfch.Tsutae/Data/.tsutae/
```

For command-line tools or tests without the app sandbox, it resolves to:

```text
~/.tsutae/
```

Tests can override the root with:

```bash
TSUTAE_ROOT=/path/to/test/root
```

## Files

- `config.yml`: main app configuration.
- `hotkeys.yml`: global hotkey and HUD configuration.
- `recipes/`: local automation recipes.
- `models/`: downloaded local STT, TTS, and VAD models.
- `logs/stt-perf.log`: runtime performance and diagnostic events.
- `logs/asr-samples.jsonl`: ASR samples. Debug builds write this by default unless `TSUTAE_ASR_SAMPLE_LOG=0`; release builds write it only when `TSUTAE_ASR_SAMPLE_LOG=1`.

API keys and tokens are stored in macOS Keychain. Config files keep only references or hashes.

## Local Build

```bash
just build
just test-core
just restart
```

`just restart` builds and launches a development app from `dist/Tsutae.app`.
The app is not Developer ID signed or notarized yet, so this repository currently expects local builds rather than downloadable release packages.

## Logs

```bash
just logs
```

This tails `stt-perf.log` from the sandbox container when present, and falls back to `~/.tsutae/logs/stt-perf.log` for non-sandbox runs.
