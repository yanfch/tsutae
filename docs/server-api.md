# Tsutae Server API

Tsutae exposes a localhost HTTP API for local tools and external clients.

Default base URL:

```text
http://127.0.0.1:1338
```

## Authentication

Token auth is optional. When `server.requireToken` is enabled, every `/v1/*` request must include:

```http
Authorization: Bearer tsutae_<token>
```

Tokens are created in Settings > Server > Applications. Each token belongs to one client and has scopes. When a request is authenticated, Tsutae uses that client as the source for playback and hook routing.

Default client scopes:

| Scope | Allows |
| --- | --- |
| `state` | `GET /v1/state` |
| `models` | `GET /v1/models`, `GET /v1/tts/voices` |
| `transcribe` | `POST /v1/audio/transcriptions` |
| `audioSpeech` | `POST /v1/audio/speech` |
| `speak` | `POST /v1/speak` |
| `notify` | `POST /v1/notify` |
| `stop` | `POST /v1/stop` |

Advanced scopes:

| Scope | Allows |
| --- | --- |
| `listen` | `POST /v1/listen`, currently not implemented |
| `recipes` | `GET /v1/recipes`, `GET /v1/recipes/:name` |
| `secrets` | `GET /v1/secrets`, names only |
| `configRead` | `GET /v1/config` |

## Health

### `GET /health`

No token required. Returns process and engine health.

```json
{
  "status": "ok",
  "version": "0.0.1",
  "engines": {
    "stt": 1,
    "tts": 2,
    "vad": 0
  }
}
```

## State

### `GET /v1/state`

Requires `state`.

Returns current app state, latest transcript, currently spoken text, current speaking source, and the TTS playback snapshot.

## Models

### `GET /v1/models`

Requires `models`.

Returns available STT, TTS, and VAD engines.

### `GET /v1/tts/voices`

Requires `models`.

Query parameters:

| Name | Required | Notes |
| --- | --- | --- |
| `engine` | No | Filter voices by engine id. Omit to return all TTS voice groups. |

Example:

```bash
curl "http://127.0.0.1:1338/v1/tts/voices?engine=fluidaudio-local-tts" \
  -H "Authorization: Bearer tsutae_<token>"
```

## STT

### `POST /v1/audio/transcriptions`

Requires `transcribe`.

OpenAI-compatible multipart transcription endpoint.

Content type:

```http
Content-Type: multipart/form-data
```

Form fields:

| Name | Required | Notes |
| --- | --- | --- |
| `file` | Yes | WAV PCM16 or raw PCM16 audio. Max body size is 25 MB. |
| `language` | No | Language hint, for example `zh` or `en`. |
| `model` | No | Model hint. Current routing may still use the configured STT route. |
| `response_format` | No | `json`, `verbose_json`, or `text`. Default is `json`. |
| `sample_rate` | Raw PCM only | Defaults to `16000` if omitted. |
| `channels` | Raw PCM only | Defaults to `1` if omitted. |

Example:

```bash
curl http://127.0.0.1:1338/v1/audio/transcriptions \
  -H "Authorization: Bearer tsutae_<token>" \
  -F file=@speech.wav \
  -F language=zh \
  -F response_format=json
```

JSON response:

```json
{
  "text": "hello",
  "language": "en",
  "duration": 1.25
}
```

When `response_format=text`, the response body is plain text.

## TTS Audio Export

### `POST /v1/audio/speech`

Requires `audioSpeech`.

OpenAI-compatible speech synthesis endpoint. Returns binary audio.

Headers:

```http
Content-Type: application/json
```

Body:

| Name | Required | Notes |
| --- | --- | --- |
| `input` | Yes | Text to synthesize. |
| `model` | No | Remote model override. |
| `voice` | No | Voice id string, or an object with an `id` field. |
| `instructions` | No | Remote style instructions. |
| `response_format` | No | Omit or use `wav`. Other values are rejected. |
| `request_style` | No | `audioSpeech` or `chatCompletionsAudio`. |

Example:

```bash
curl http://127.0.0.1:1338/v1/audio/speech \
  -H "Authorization: Bearer tsutae_<token>" \
  -H "Content-Type: application/json" \
  -o speech.wav \
  -d '{
    "input": "Build finished.",
    "voice": "alloy",
    "response_format": "wav"
  }'
```

Response headers include a content type such as `audio/wav` and `Content-Disposition: attachment; filename=tsutae-tts.wav`.

## TTS Playback

### `POST /v1/speak`

Requires `speak`.

Speaks text on this Mac and shows the speaking capsule.

Body:

| Name | Required | Notes |
| --- | --- | --- |
| `text` | Yes | Text to speak. Empty text is rejected. |
| `source` | No | Caller label. Ignored when the request is authenticated with a client token; the client name is used instead. |
| `interrupt` | No | If true, replace current playback. If false, queue behavior follows TTS settings. |
| `voice` | No | Voice id override. |
| `rate` | No | Playback rate override. |
| `presentationStyle` | No | `standard` or `minimal`. Defaults to the TTS setting. |

Example:

```bash
curl http://127.0.0.1:1338/v1/speak \
  -H "Authorization: Bearer tsutae_<token>" \
  -H "Content-Type: application/json" \
  -d '{
    "text": "Build finished.",
    "interrupt": true,
    "presentationStyle": "standard"
  }'
```

Response:

```json
{
  "ok": true,
  "state": "speaking",
  "source": "Codex",
  "presentationStyle": "standard",
  "queueLength": 0
}
```

### `POST /v1/notify`

Requires `notify`.

Delivers spoken alerts, macOS notifications, or both.

Body:

| Name | Required | Default | Notes |
| --- | --- | --- | --- |
| `message` | Yes |  | Text to speak or show. Empty text is rejected. |
| `title` | No | `Tsutae` | macOS notification title. |
| `level` | No | `info` | `info`, `warning`, or `error`. Errors use time-sensitive notification level. |
| `voice` | No | current TTS voice | Voice id override for spoken alert. |
| `duration` | No | `short` | `short` or `long`. |
| `interruptible` | No | TTS setting | Whether spoken alert can interrupt current playback. |
| `fallback_to_notification` | No | `true` | If speech fails, try macOS notification. |
| `notify` | No | `false` | Deliver a macOS notification. |
| `speak` | No | `true` | Speak the message. |
| `sound` | No | notification setting | Override notification sound for this request. |
| `click_action` | No | `default` | `default`, `settings`, or `tsutae` opens Tsutae. `none`, `noop`, or `ignore` does nothing. |
| `open_url` | No |  | URL to open when the notification is clicked, for example `codex://`. |
| `activate_bundle_id` | No |  | Bundle id to activate when clicked, for example `com.openai.codex`. |

Example, notify only and return to Codex on click:

```bash
curl http://127.0.0.1:1338/v1/notify \
  -H "Authorization: Bearer tsutae_<token>" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Codex",
    "message": "Codex needs input.",
    "level": "info",
    "notify": true,
    "speak": false,
    "sound": true,
    "open_url": "codex://",
    "activate_bundle_id": "com.openai.codex"
  }'
```

Example, no click action:

```json
{
  "message": "Background task finished.",
  "notify": true,
  "speak": false,
  "click_action": "none"
}
```

Response:

```json
{
  "ok": true,
  "spoken": false,
  "notificationDelivered": true,
  "fallbackUsed": false,
  "level": "info",
  "state": null,
  "queueLength": 0,
  "error": null
}
```

### `POST /v1/stop`

Requires `stop`.

Stops current TTS playback and clears queued speech.

Response:

```json
{
  "ok": true,
  "state": "stopping"
}
```

## Recipes And Secrets

### `GET /v1/recipes`

Requires `recipes`.

Lists saved recipes.

### `GET /v1/recipes/:name`

Requires `recipes`.

Loads one recipe by name.

### `GET /v1/secrets`

Requires `secrets`.

Lists secret reference names only. Secret values are never returned.

## Config

### `GET /v1/config`

Requires `configRead`.

Returns the current config. This is an advanced permission and should only be granted to trusted clients.

## Listen

### `POST /v1/listen`

Requires `listen`.

Reserved for future live-listening control. Currently returns a not implemented error.

## Hooks

Hooks are outbound callbacks from Tsutae to a configured client URL. They are not API-call permissions.

Events:

| Event | When |
| --- | --- |
| `onTranscribed` | STT completes successfully. |
| `onSpoken` | TTS playback starts or queues successfully. |
| `onError` | A server-handled operation fails. |

When a request uses a client token, Tsutae sends hooks configured for that client. Without an authenticated client, Tsutae falls back to global server hooks.
