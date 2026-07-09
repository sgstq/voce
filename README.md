<div align="center">

<img src="Voce/Assets.xcassets/AppIcon.appiconset/icon_256.png" width="96" alt="Voce" />

# Voce

**Push-to-talk dictation for macOS.**
Hold a key, speak, and polished text lands at your cursor — in any app.

![macOS](https://img.shields.io/badge/macOS-26%2B-000000?logo=apple&logoColor=white)
[![Download](https://img.shields.io/github/v/release/sgstq/voce?label=download&color=2ea043)](https://github.com/sgstq/voce/releases/latest)

<br />

[**⬇ Download Voce**](https://github.com/sgstq/voce/releases/latest)<br />
<sub>Apple Silicon · macOS 26+</sub>

<br />

<img src="assets/typing.gif" width="760" alt="Dictating into an editor with Voce" />

</div>

## Features

- **Talk anywhere** — hold your hotkey, speak, release. Text appears wherever your cursor is: editors, chat, browsers, terminals.
- **Polished, not raw** — a cleanup pass fixes grammar, punctuation, and filler words, and matches the style of the text already around your cursor.
- **Fast** — streaming transcription; your words show up in about a second.
- **Live overlay** — a floating waveform and words that appear as you speak. It never steals focus and disappears when you're done.
- **Multilingual** — detects the spoken language automatically and keeps mid-sentence language switches intact.
- **Private by choice** — run the cleanup fully on-device with Apple Intelligence: no API key, no network. Cloud providers (OpenAI, Groq, Cerebras) are optional.
- **Clipboard-safe** — text is typed as real keystrokes, so your clipboard and its history are never touched.
- **Out of the way** — lives in the menu bar with no Dock icon, launches at login, and uses near-zero CPU while idle.

## Install

**[⬇ Download the latest release](https://github.com/sgstq/voce/releases/latest)** — open the DMG and drag **Voce** into Applications.

Or build from source (requires Xcode):

```bash
scripts/install.sh          # builds and installs Voce to /Applications
scripts/package.sh 0.1.0    # or build a drag-to-install DMG in dist/
```

## Setup

On first launch:

1. Grant **Microphone** and **Accessibility** in System Settings → Privacy & Security. Accessibility lets Voce type into other apps and read the text around your cursor.
2. Open **Settings**, pick a transcription backend, and paste your OpenAI API key (kept in the macOS Keychain).
3. Record a **push-to-talk key** — function keys and modifiers (Fn, ⌥, ⌘…) work best.
4. Hold it, speak, release.

<div align="center">
  <img src="assets/settings.gif" width="480" alt="Voce settings" />
</div>

## Privacy

Voce stores no recordings or transcripts. Audio goes to your chosen provider only for the moment it's transcribed, and the cleanup pass can run entirely on-device with Apple Intelligence — no key, no network. Your API keys stay in the macOS Keychain.

## Requirements

- macOS 26 or later, Apple Silicon
- Microphone and Accessibility permissions
- An OpenAI API key for transcription (the on-device cleanup needs no key)

---

Warning
---
<div align="center">


  <b>ALL CODE AND SCRIPTS IN THIS REPOSITORY—EVEN THOSE BASED ON REAL DOCUMENTATION—ARE ENTIRELY EXPERIMENTAL. ALL LOGIC WAS HALLUCINATED BY MATRIX MULTIPLICATIONS….. HAPHAZARDLY. THE FOLLOWING REPOSITORY CONTAINS UNTESTED CODE AND DUE TO ITS CONTENT IT SHOULD NOT BE USED ANYWHERE BY ANYONE ■</b>

  <img src="assets/warning.png" width="200" alt="Warning" />
</div>
