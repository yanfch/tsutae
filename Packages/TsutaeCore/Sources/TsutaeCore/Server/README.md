# Server

Hummingbird HTTP server exposing Tsutae's local automation API.

## Current Surface

- `GET /health` — process and engine health.
- `GET /v1/state` — app state, latest transcript, and TTS playback snapshot.
- `GET /v1/config` — read current config. Requires the advanced `configRead` scope when token auth is enabled.
- `GET /v1/models` — list STT/TTS/VAD engines.
- `GET /v1/tts/voices?engine=...` — list TTS voices, optionally filtered by engine.
- `POST /v1/audio/transcriptions` — OpenAI-compatible multipart STT upload.
- `POST /v1/audio/speech` — OpenAI-compatible TTS audio synthesis. Returns binary audio.
- `POST /v1/speak` — enqueue or interrupt spoken playback.
- `POST /v1/notify` — deliver spoken and/or system notifications.
- `POST /v1/stop` — stop current TTS playback.
- `GET /v1/recipes`, `GET /v1/recipes/:name` — read saved recipes.
- `GET /v1/secrets` — list secret reference names only. Secret values are never returned.
- `POST /v1/listen` — reserved for future live-listening control; currently returns not implemented.

## Auth

Token auth is optional by config. When `server.requireToken` is enabled, callers must send:

```http
Authorization: Bearer tsutae_<token>
```

Tokens are issued per server client. Each client has scopes such as `state`, `models`, `transcribe`, `audioSpeech`, `speak`, `notify`, and `stop`. Advanced scopes include `listen`, `recipes`, `secrets`, and `configRead`.

## Hooks

`ServerHooks.swift` sends outbound callbacks for:

- `onTranscribed`
- `onSpoken`
- `onError`

Hooks can be configured globally or per server client. Requests authenticated with a client token use that client's hook configuration instead of falling back to global hooks.

## Constraints

- Bind localhost by default.
- JSON is used for all non-binary responses.
- `/v1/audio/speech` returns binary audio.
- `/v1/listen` is still planned and intentionally not implemented.
