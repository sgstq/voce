# Strategy

## What Voce is
A fast, native macOS push-to-talk dictation utility. Hold a global hotkey, speak, release; the audio is transcribed (cloud-first via OpenAI Realtime, with modern local speech as the offline path), optionally refined by an LLM, and the final text is inserted into whatever field has focus. It lives in the menu bar.

## Background
Voce is a ground-up rewrite of `duper-disper`, a cross-platform (Windows + macOS) prototype written in Rust with an egui UI. On paper it had all the features; in practice it was slow, memory-heavy, visually off-target, and unreliable. A code review traced the causes to the **architecture, not incidental bugs** — i.e. not fixable by patching.

## Why rewrite instead of fix
Root causes found in the prototype:

1. **Wrong UI toolkit.** egui is an immediate-mode *game* UI. It cannot render the intended design (OKLCH color, vibrancy, spring motion, custom type — see `design/tokens.css`) and produced raw default styling instead.
2. **Subprocess windows.** egui wanted the main thread, but the tray needed a manual event-pump loop — so the settings window and the recording overlay each ran as *separate child processes*. The overlay was spawned fresh on every recording (a full GPU process), which is the visible lag, syncing state over stdin JSON / a config file on disk.
3. **Blocking main loop.** Transcription and LLM refinement ran synchronously on the main thread (`rt.block_on(...)`), freezing the entire app for seconds during every dictation.
4. **Memory is structural.** The footprint came from running extra GPU-backed (wgpu) UI processes plus a full async runtime — not a single leak. You can't patch your way out of that.

None of these are bugs; they're consequences of the stack. So the UI/process layer must be replaced wholesale — and going native captures that for free.

## Why native macOS (not Tauri, not keep-cross-platform)
A SwiftUI `MenuBarExtra` + AppKit `NSPanel` app gives, out of the box, exactly what the prototype fought for:
- ~20–50 MB idle instead of hundreds; one process, not three.
- An instant overlay (no process fork, no GPU init) that can actually render the design.
- Native settings, clipboard-free text insertion (`AXUIElement` / `CGEvent`), and `AXUIElement` for surrounding-text capture (a feature the prototype never implemented on macOS).
- Real background concurrency, so nothing blocks the UI.

**Tauri** (keep the Rust core + web UI) was considered and rejected: a webview carries its own memory weight, and the design's inline, field-anchored recorder is hard to do well in it. For a single-platform system utility, native wins.

**Windows is dropped.** The cross-platform abstractions (rdev / enigo / eframe) are precisely what forced the lowest-common-denominator result. Committing to one platform removes that tax. _Trade-off:_ a future Windows client would need its own native build.

## Port, don't restart
The prototype's **domain logic and macOS glue are largely sound and portable** (see `docs/PORTING.md`). We carry those over — audio math, silence/hallucination heuristics, the refinement prompt + context rules, the Realtime protocol shape, the Accessibility/CGWindow patterns — rather than rediscovering them. The rewrite is scoped as a **port of proven logic onto a native shell**, not a greenfield reinvention.

## Non-goals (v1)
- Windows / Linux.
- Cloud sync, accounts, team features.
- A full transcript-history product (basic history may come later; not v1).
