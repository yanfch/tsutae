# Engines

Pluggable STT / TTS / VAD engines.

## What goes here

Each subdirectory holds:

- A protocol (`STTEngine.swift`, `TTSEngine.swift`, `VADEngine.swift`)
- One concrete implementation per engine (file-per-engine)
- A registry / factory in `EngineRegistry.swift` (parent dir)

See workspace doc `01-voicebar.md` (引擎抽象 / 引擎实现矩阵) for the protocol shapes and which engines we plan to support.

## STT

Implementations to add (in priority order):

- `OpenAICompatibleSTT.swift` — HTTP client. Default endpoint: osaurus `:1337/v1/audio/transcriptions`. Also covers OpenAI / Groq / any compatible service.
- `WhisperKitSTT.swift` — Local. Wraps `argmaxinc/WhisperKit`. **Phase 2.**
- `AppleSpeechSTT.swift` — System `SFSpeechRecognizer`. Fallback only.
- `FluidAudioSTT.swift` — Parakeet TDT. **Phase 2.**

## TTS

- `AppleTTS.swift` — `AVSpeechSynthesizer`. Default, zero-dep.
- `OpenAICompatibleTTS.swift` — HTTP client.
- `ElevenLabsTTS.swift` — Premium voice.
- `KokoroMLXTTS.swift` — Local high quality. **Phase 2** (requires MLX-Swift).

## VAD

- `EnergyVAD.swift` — Threshold-based fallback. **MVP.**
- `SileroVAD.swift` — ONNX. **Phase 2.**

## Constraints

- Each engine is independently switchable from `config.yml`.
- Primary + fallback chain: failures auto-route to fallback (with TTS notification optional).
- Engines never read API keys directly — they receive resolved credentials from `Secrets/`.
