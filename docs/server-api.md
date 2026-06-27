# Server API

Tsutae exposes a localhost HTTP API for local tools.

Default base URL:

```text
http://127.0.0.1:1338
```

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

Token auth can be enabled in Settings > Server. Client tokens are shown once when generated; Tsutae stores token hashes in config and secret values in Keychain.

Example:

```bash
curl http://127.0.0.1:1338/health
```
