# Tracing

OpenTelemetry tracing + W3C trace context propagation.

## What goes here

See workspace doc `04-tracing.md` (full tracing design + propagation rules).

- `Tracer.swift` — global tracer setup, attribute helpers.
- `FileSpanExporter.swift` — write OTLP-JSON spans to `<tracesDir>/<YYYY-MM-DD>/tsutae.jsonl`. Daily rotation. Match the same on-disk format kanade uses, so jq cross-service queries work.
- `TraceContextHeaders.swift` — extract incoming `traceparent` (Hummingbird middleware), inject outgoing `traceparent` on URLSession requests for recipes / announcers.

## Constraints

- Default exporter: `file`. `otlp_http` is supported but optional (V2).
- Span attributes follow OTel GenAI conventions (`gen_ai.*`) plus our extensions (`stt.*`, `tts.*`, `vad.*`).
- For STT spans: include `stt.audio_duration_ms`, `stt.engine`, `stt.rtf`, `stt.ttfw_ms`.
- For TTS spans: include `tts.engine`, `tts.input_chars`, `tts.output_audio_ms`, `tts.ttfa_ms`.
- The on-disk OpenTelemetry-Swift SDK is heavyweight. MVP path: hand-rolled span model + JSONEncoder (saves dependency, easy to control format). See workspace doc 04-tracing.md §Swift 端.
