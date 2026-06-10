# Requirements

## Functional

### Core dictation loop
- **Global push-to-talk hotkey** — configurable; hold to record, release to finish.
- **Microphone capture** starts on key-down, stops on key-up; the mic is never held while idle.
- **Transcription backends** (configurable):
  - **OpenAI Realtime** (streaming, default) — live partial transcript while speaking.
  - **Local speech** (offline fallback, preferably macOS 26 `SpeechAnalyzer` / `SpeechTranscriber`; use Whisper only if it wins on quality, languages, or device availability).
  - _(Later)_ other cloud STT (Deepgram / Groq / OpenAI REST).
- **Live preview overlay** — a floating, non-activating panel showing recording state + streaming text; never steals focus.
- **Optional LLM refinement** — clean up the raw transcript (punctuation, filler removal, formatting) via an OpenAI-compatible API; runs off the main thread.
- **Text insertion** into the focused field of any app — **clipboard-free by default; must not disturb the clipboard or its history** (see _Text insertion_ below).
- **Guards** — skip empty / too-short / silent / hallucinated results.
- **Target-changed guard** — if focus moved to a different app or field between release and insertion, do not paste into the wrong place.

### Text insertion (clipboard-safe — hard requirement)
The user's clipboard and clipboard history must **not** be disturbed by dictation. The common dictation pattern — _save clipboard → write text → ⌘V → restore_ — pollutes clipboard-history managers: every write **and** the restore is recorded, and the restore reorders/mangles the user's "recent items." Voce avoids this. Insertion strategy, in priority order:

1. **Synthesized Unicode keystrokes (default — no clipboard).** Inject text via `CGEventKeyboardSetUnicodeString`, which "types" the characters directly without ever touching the pasteboard and handles full Unicode. Modifier flags are stripped from synthesized events, and insertion waits for the push-to-talk key to be physically released so held modifiers can't turn text into shortcuts.
2. **Accessibility insertion (opt-in mode — no clipboard).** Insert at the cursor via `AXUIElement` (`kAXSelectedTextAttribute`). Keeps the field's native undo, but many apps (Chromium/Electron fields) report success without inserting anything, so it is not the default probe.
3. **Clipboard paste (fallback — automatic only on failure, or opt-in).** Used only when 1–2 don't work (some terminal/Electron apps, or very long text). When used it must be **history-safe**: mark the pasteboard write with `org.nspasteboard.TransientType` (+ `ConcealedType`) so compliant managers (Maccy, Raycast, Paste, Alfred…) never record it, then restore the prior contents reliably (wait for the paste to land; mark the restore `org.nspasteboard.RestoredType`). Never leave dictated text sitting on the clipboard.

**Hard requirement:** the _default_ insertion path uses **no clipboard at all**; any clipboard fallback must be invisible to clipboard-history tools.

### Context (improves refinement quality)
- Capture active app name + window title.
- Capture surrounding / selected text via Accessibility (`AXUIElement`) — _new on macOS vs. the prototype._
- Optional screenshot context with per-app rules (in-process via ScreenCaptureKit).

### Settings
- Hotkey, insertion mode (auto · accessibility · keystrokes · clipboard-fallback), language.
- Backend selection + API keys (stored in **Keychain**, never plaintext).
- Refinement on/off, model, prompt.
- Context rules (per-app screenshot/context toggles).
- Theme (light / dark / auto) + accent, per the design.
- Live diagnostics (mic input, API connectivity, latency).

### Lifecycle
- Menu-bar app, no Dock icon; the icon reflects recording state.
- Launch at login (`SMAppService`).
- Single instance.
- First-run onboarding: permissions (Accessibility + Microphone) and API-key entry.

## Non-functional
- **Latency:** overlay appears instantly on key-down; first partial transcript < ~500 ms after speech (cloud); end-to-end raw→inserted target < ~2 s for short utterances.
- **Memory:** < ~80 MB idle.
- **Responsiveness:** the UI never blocks — transcription / refinement / network run off the main actor.
- **Privacy:** API keys in Keychain; local mode keeps audio on device; no telemetry without consent.
- **Distribution:** signed + notarized DMG (no Gatekeeper right-click dance).
- **Reliability:** clean failure UX (mic denied, API error, network down) surfaced in the overlay; never silently lose a dictation.
- **Platform baseline:** target modern macOS first. Avoid older deployment targets when they force weaker local speech, AI, capture, or reliability choices.

## Permissions required
- **Accessibility** — global hotkey + text insertion.
- **Microphone** — recording.
- **Screen Recording** _(optional)_ — only if screenshot context is enabled.
