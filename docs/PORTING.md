# Porting from `duper-disper` (reference only)

The old Rust repo (`../duper-disper`) is a **reference, not a dependency**. Port the *logic*, not the architecture. The prototype's domain code is largely sound; its UI/process model is what we're discarding (see `STRATEGY.md`).

## Worth porting (logic / constants)
- **Audio** — `src/audio/mod.rs`: linear resample; RMS energy; thresholds — *silence* if `RMS < 0.005`, *too short* if `< 1600` samples (~0.1 s @ 16 kHz); mono mixing.
- **Refinement** — `src/refinement/mod.rs`: the LLM prompt construction and the context-rules system (per-app screenshot/context matching). The prompt is the valuable part.
- **Realtime** — `src/transcription/realtime.rs`: the session *state-machine shape* (connect → `session.update` → append audio → commit → deltas → completed → closed). Protocol verified against the GA API (below).
- **Context / macOS glue** — `src/context/mod.rs`, `src/macos.rs`: active app via `NSWorkspace.frontmostApplication`; window title via `CGWindowListCopyWindowInfo`. The macOS FFI here is correct and is a good Swift reference. Note: surrounding-text capture was never implemented — add it natively with `AXUIElement`.
- **Config schema** — `src/config/mod.rs`: a reasonable starting field set. Move API keys to Keychain.
- **Tests** — the audio / realtime unit tests encode expected behavior worth re-asserting in Swift.

## Do NOT port
- The egui UI (`src/ui/*`), the subprocess overlay/settings model, the polling main loop, `rt.block_on` on the main thread, rdev / enigo / arboard usage, and all Windows-specific code.
- **The clipboard insertion approach** in `src/insertion/mod.rs` — it does _save → set clipboard → ⌘V → `sleep(100 ms)` → restore_, which pollutes clipboard-history managers and races. Voce must insert **without the clipboard by default** (Accessibility → Unicode keystrokes), with a history-safe (`org.nspasteboard.TransientType`) clipboard path only as a fallback. See the *Text insertion* requirement in `REQUIREMENTS.md`.

## OpenAI Realtime protocol (verified 2026-06-09 against the GA docs)
The wire protocol Voce implements — confirmed against the current OpenAI Realtime transcription guide, and matching the prototype's schema:

- **URL:** `wss://api.openai.com/v1/realtime?intent=transcription`, `Authorization: Bearer <key>`.
- **Configure:** send `session.update` with `session.type = "transcription"`, `session.audio.input.format = {"type": "audio/pcm", "rate": 24000}`, `session.audio.input.transcription = {"model", "language", "delay"}`, and `session.audio.input.turn_detection = null` (push-to-talk = no server VAD).
- **Models:** `gpt-realtime-whisper` (streaming deltas; Voce default). `gpt-4o-transcribe` / `gpt-4o-mini-transcribe` / `whisper-1` also exist.
- **Audio:** 24 kHz mono PCM16, base64, via `input_audio_buffer.append`; manual `input_audio_buffer.commit` on key release.
- **Server events:** `session.updated`/`session.created` (ready), `conversation.item.input_audio_transcription.delta`, `…input_audio_transcription.completed` (final `transcript`), `error`.

If transcription misbehaves, re-verify against the live docs before changing the wire shape.

## Native upgrades to make during the port
- API keys → **Keychain** (was plaintext TOML).
- Local speech → prefer macOS 26 **SpeechAnalyzer / SpeechTranscriber** for the offline path; port Whisper only if it clearly beats the native stack for required languages, accuracy, or device support.
- Surrounding-text context → **AXUIElement** (was missing on macOS).
- Screenshot → **ScreenCaptureKit**, in-process (was a `screencapture` subprocess).
- Autostart → **SMAppService** (was a LaunchAgent plist).
- Text insertion → **AXUIElement + CGEvent**, with history-safe `NSPasteboard` only as a fallback (was enigo / arboard).
