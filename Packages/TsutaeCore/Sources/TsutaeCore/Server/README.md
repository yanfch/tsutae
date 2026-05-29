# Server

Hummingbird HTTP server exposing tsutae's API. See workspace doc `01-voicebar.md` (对外 API) and `07-integration.md` for action framework details.

## What goes here

- `Server.swift` — Hummingbird app builder; wires routes; binds `127.0.0.1:1338`.
- `Routes/Audio.swift` — OpenAI-compatible: `POST /v1/audio/transcriptions`, `POST /v1/audio/speech`.
- `Routes/Edge.swift` — Sidecar-specific: `POST /v1/listen` (SSE), `POST /v1/speak`, `POST /v1/stop`, `GET /v1/state`, `WS /v1/events`.
- `Routes/Notify.swift` — Inbound notifications: `POST /v1/notify` (other tools push messages here).
- `Routes/Health.swift` — `GET /health` (status of each engine + uptime).
- `Routes/Config.swift` — `GET /v1/config`, `PUT /v1/config`, `POST /v1/diagnose`, `POST /v1/recipes/:name/test`.

## Constraints

- Bind localhost only by default.
- All non-streaming responses are JSON.
- `/v1/listen` SSE protocol matches workspace doc `01-voicebar.md` §协议示例.
- W3C `traceparent` header propagation: extract from incoming requests, inject on outgoing recipe POST calls.
