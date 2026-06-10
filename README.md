# Voce

**Voce** (Italian for *voice*) is a fast, native **macOS** push-to-talk dictation app: hold a hotkey, speak, and polished text lands at your cursor in any app — in under two seconds.

Voce is a ground-up native rewrite (SwiftUI + AppKit) of an earlier cross-platform Rust/egui prototype ([duper-disper](https://github.com/sgstq/duper-disper)). It keeps the proven domain logic and discards the UI/process architecture that made the prototype slow, memory-heavy, and unable to match the intended design.

### Warning
<p align="center">
  <img src="assets/warning.png" width="72" alt="Warning">
</p>
<p align="center">
  <b>ALL CODE AND SCRIPTS IN THIS REPOSITORY—EVEN THOSE BASED ON REAL DOCUMENTATION—ARE ENTIRELY EXPERIMENTAL. ALL LOGIC WAS HALLUCINATED BY MATRIX MULTIPLICATIONS….. HAPHAZARDLY. THE FOLLOWING REPOSITORY CONTAINS UNTESTED CODE AND DUE TO ITS CONTENT IT SHOULD NOT BE USED ANYWHERE BY ANYONE ■</b>
</p>

---

## Features

- **Push-to-talk** — hold a recordable hotkey (F-keys or modifiers: Fn, Right ⌥, ⌘…), release to transcribe, refine, and insert.
- **Live preview overlay** — voice-reactive waveform, words materializing as you speak, soft typing dots, shimmer while polishing. Never steals focus; zero CPU while hidden.
- **Streaming transcription** — OpenAI Realtime (`gpt-realtime-whisper`) over WebSocket with live deltas.
- **Context-aware refinement** — an LLM cleanup pass fed with the text around your cursor (via Accessibility), so identifiers keep their exact casing and mid-sentence dictation continues the sentence. Providers: OpenAI, Groq, Cerebras, or **Apple on-device** (no network, no key).
- **Multilingual** — automatic language detection, mid-dictation language switches preserved; a deterministic gate rejects refiner output that translated or truncated the dictation (the raw transcript wins).
- **Clipboard-free insertion** — text is typed via synthesized Unicode keystrokes; your clipboard and clipboard-history manager are never touched. History-safe transient clipboard exists only as an opt-in fallback.
- **Safety guards** — silence/too-short gates, focus-change guard (never types into the wrong app), refusal/truncation/translation gates on refinement.
- **Menu-bar native** — no Dock icon, state-reactive icon, launch-at-login (System Settings Login Items), API keys in the Keychain, ~75 MB and 0% CPU idle.

## Install

**[⬇ Download the latest release](https://github.com/sgstq/voce/releases/latest)** — open the DMG and drag Voce into Applications.

Or build and install locally (signed with a stable identity, so updates keep your permission grants):

```bash
scripts/install.sh                 # signed Release build → /Applications/Voce.app
# or
scripts/package.sh 0.x.y           # → dist/Voce-0.x.y.dmg (drag-to-install)
```

On first run, grant **Microphone** and **Accessibility** (System Settings → Privacy & Security), add your OpenAI API key in Settings, record a push-to-talk key, and dictate.

## Documents
- [docs/STRATEGY.md](docs/STRATEGY.md) — why a native macOS rewrite, and what we keep vs. discard
- [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md) — what Voce must do (functional + non-functional)
- [docs/PLAN.md](docs/PLAN.md) — phased roadmap and the Rust→native component map
- [docs/PORTING.md](docs/PORTING.md) — what was ported from the old Rust code

## Design
The visual spec lives in [`design/`](design/) (the "Cadence" exploration: tokens, mockups, screenshots). [`design/tokens.css`](design/tokens.css) is the source of truth for color, type, spacing, and motion.

## Development
Voce uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) so `project.yml` is the source of truth for the Xcode project. The baseline is macOS 26+ with Swift 6, so local speech and Apple Intelligence-era APIs can be first-class instead of optional compatibility paths.

```bash
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project Voce.xcodeproj -scheme Voce -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
```

Diagnostics: the whole pipeline logs stage-by-stage under the `com.sgstq.voce` subsystem —

```bash
log stream --predicate 'subsystem == "com.sgstq.voce"' --info
```

## Target
macOS 26+ · Swift 6 · menu-bar app (no Dock icon) · SwiftUI + AppKit · cloud-first (OpenAI Realtime) with Apple on-device refinement and modern local speech as the offline path.
