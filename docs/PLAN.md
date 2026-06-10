# Implementation Plan

## Architecture
- **Menu-bar app:** `MenuBarExtra` (or `NSStatusItem`) for the menu; an AppKit `NSPanel` (non-activating, borderless, click-through, always-on-top, joins all Spaces) for the floating overlay.
- **UI:** SwiftUI for settings + menu content; the overlay rendered with SwiftUI / Core Animation inside the panel.
- **Concurrency:** Swift 6 `async`/`await` + actors for audio, networking, transcription — nothing blocks the main actor.
- **Targets:** macOS 26+. XcodeGen-managed Xcode project → archive → codesign → notarized DMG.
- **Baseline choice:** optimize for the best modern macOS implementation, not broad legacy compatibility. Use current Apple APIs as default paths when they materially improve latency, privacy, reliability, or user experience.

## Phases

### Phase 0 — Scaffold
XcodeGen-managed macOS menu-bar app (`LSUIElement`), status item with a state-reactive icon, empty SwiftUI settings window, `Codable` config model, API key in Keychain, code signing set up. Builds and runs as a do-nothing menu-bar app.

### Phase 1 — "It works" (cloud-first dictation loop)
`CGEventTap` hold-to-record → `AVAudioEngine` capture (+ resample to 24 kHz) → OpenAI Realtime WebSocket (`gpt-realtime-whisper`; see PORTING.md) → `NSPanel` live preview → release → clipboard-free insertion into the focused field (Accessibility first, Unicode keystrokes second). End-to-end dictation that actually inserts text. This is the whole product for a cloud user.

### Phase 2 — Refinement + context
Port the refinement prompt + context-rules; `AXUIElement` surrounding-text + active-app capture; ScreenCaptureKit screenshot; target-changed guard; silence/hallucination filters.

### Phase 3 — Design polish (stop being ugly)
Implement the design system from `design/tokens.css`: the live recorder (waveform, pulse, shimmer "polishing" state, field-anchored position), the full settings UI from the mockups, light/dark + accent.

### Phase 4 — Local + ship
Local speech fallback (prefer macOS 26 `SpeechAnalyzer` / `SpeechTranscriber`; use whisper.cpp only if Apple Speech quality, language coverage, or availability is insufficient); diagnostics; launch-at-login; notarized DMG in CI.

## Rust → native component map
| Concern | Old (Rust) | Native replacement |
|---|---|---|
| Hotkey | rdev | `CGEventTap` (keyDown/keyUp) |
| Audio capture + resample | cpal + manual | `AVAudioEngine` + `AVAudioConverter` |
| Realtime STT | tokio-tungstenite | `URLSessionWebSocketTask` (fix protocol) |
| Cloud/REST STT + refine | reqwest | `URLSession` (async) |
| Local STT | whisper-rs | macOS 26 `SpeechAnalyzer` / `SpeechTranscriber`; whisper.cpp only as a fallback |
| Active app / window | CGWindowList | `NSWorkspace` + `CGWindowList` |
| Surrounding text | _(missing)_ | `AXUIElement` `kAXSelectedText` / `kAXFocusedUIElement` |
| Screenshot | `screencapture` subprocess | ScreenCaptureKit (in-process) |
| Text insertion | enigo / arboard | `AXUIElement` + `CGEvent`; history-safe `NSPasteboard` only as fallback |
| Settings UI | egui (~1.7k LOC) | SwiftUI `Form` / `Picker` |
| Overlay | egui subprocess @30 fps | `NSPanel` + SwiftUI / Core Animation |
| Tray / menu bar | tray-icon | `MenuBarExtra` / `NSStatusItem` |
| Config + secrets | plaintext TOML | `Codable` JSON + **Keychain** |
| Single instance | named mutex / unix socket | default on macOS |
| Autostart | LaunchAgent plist | `SMAppService` |
| Packaging | cargo-bundle | Xcode archive → notarized DMG |

## Highest-risk unknown
The OpenAI Realtime transcription protocol must stay aligned with the current GA transcription-session API. Use `gpt-realtime-whisper`, 24 kHz mono PCM, `session.update` with `session.type = "transcription"`, `audio.input.transcription`, `input_audio_buffer.append`, and manual `input_audio_buffer.commit` for push-to-talk. See `docs/PORTING.md`.
