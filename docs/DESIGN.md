# Design

Voce should look like part of macOS, not like a web app in a window. When a choice is unclear, do what the system and the best dictation apps do. Don't invent decoration.

## What the market does (researched September 2026)
- **Wispr Flow**, the one to beat: a small black capsule at the bottom centre. White bars follow your voice. It shows no live transcript, on purpose ("prioritized responsiveness over visible feedback"). Its one widely heard complaint is that the pill can't be moved and covers content.
- **VoiceInk** (open source, so sizes are known): a black capsule 184×40pt, 24pt above the Dock. It has 15 bars, each 3pt wide with 2pt gaps and 4–28pt tall, tallest in the centre. It widens only when the opt-in live text arrives, using springs of about 0.4 response and 0.8 damping.
- **Superwhisper**: a regular window and a mini window (waveform only), plus an option for no window at all.
- **Onboarding** (Wispr): one card per permission, each granted card revealing the next, then straight into a first dictation.
- **Apple HIG**: keep HUDs small, and "don't let a HUD… compete with the content". Use colour sparingly.

What to avoid:
- big fixed overlays
- "Listening…" labels
- grey words streaming in with typing dots
- purple/indigo gradients, glow, sparkles
- rounded cards with soft shadows everywhere
- tinting everything

## Decisions
- **Overlay:** a near-black capsule, 36pt tall, 24pt above the visible frame, bottom centre.
  - It always renders dark, like a HUD, so it reads the same over any content.
  - Thirteen white bars, tallest in the centre, driven by the real mic level. The newest level sits in the centre and ripples outward. In silence the bars rest as dots.
  - While finalizing or polishing, the bars settle to dots and a light sweeps across them.
  - Errors widen the capsule to show a red-tinted icon and a short sentence.
  - There are no text labels for state.
  - The live transcript is opt-in (Settings → General). When it is on, it appears as one line with the head truncated, in a fixed-width strip, so the capsule doesn't jitter.
- **Motion:** springs only. The capsule rises from 60% scale on entry and fades out in about 150ms on exit. Only size changes animate; per-word text updates never do.
- **Colour:** the overlay is monochrome. The accent defaults to the macOS system accent. The optional accents are muted versions of the system colours, softer still in dark mode, and they tint controls only. The Settings sidebar keeps the native system-accent highlight.
- **Windows:** native SwiftUI grouped `Form`s everywhere.
  - Settings is a sidebar window like System Settings: General, Transcription, Polish, Context, Permissions.
  - Advanced fields (model ids, latency) sit in their own section.
  - An API key field shows Save only while it differs from what is stored.
- **First run:** a welcome window with Microphone, Accessibility and "Transcribe with" in one form.
  - Each step ticks itself off as macOS reports the grant (checked every second while the window is open).
  - It finishes with "Hold [key] anywhere and speak."
  - The menu-bar icon shows a badge and the menu offers "Finish Setting Up…" until setup is done.
- **Menu:** a status line, then Settings… (⌘,) and Quit. Permission details live in Settings.

## Next candidates (not built)
- Esc to cancel while recording.
- A setting for the overlay's position (bottom / top / notch) and to hide it.
- Optional start/stop sounds.
- History of recent dictations in the menu.
