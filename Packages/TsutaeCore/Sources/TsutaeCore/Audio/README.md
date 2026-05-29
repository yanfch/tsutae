# Audio

Microphone capture, playback, audio engine plumbing.

## What goes here

- `AudioInput.swift` — `AVAudioEngine` mic capture; emits 16kHz mono PCM frames to subscribers (VAD + STT).
- `AudioOutput.swift` — playback queue for TTS audio; supports interruption / stop.
- `AudioFormat.swift` — sample format constants, conversion helpers.

## Constraints

- Always 16kHz mono PCM internally. VAD models + most STT engines expect this.
- Microphone permission: request on first hotkey press, surface clear error if denied.
- Echo cancellation: enable `AVAudioSession` voice processing mode for barge-in scenarios (TTS playing + user speaks).
- Output queue must support interruption from `POST /v1/stop` and from VAD-detected user speech (barge-in).
