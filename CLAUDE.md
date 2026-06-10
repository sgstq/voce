# Agent Instructions

These instructions describe how AI coding agents should work in this repository.

## Clarify Before Acting
- Ask questions when the request, current behavior, or desired behavior is unclear.
- State assumptions before implementation.
- If a simpler approach exists, mention it before choosing a larger one.

## Planning First
- Do not implement code changes until the user explicitly asks with words like "implement", "build it", "go ahead", or similar.
- When the user asks a question, answer the question only. Do not make code changes unless explicitly asked.
- For multi-step work, give a short plan with verification steps before editing.

## Simplicity
- Make the smallest change that solves the stated problem.
- Do not add speculative features, unused abstractions, or configurability that was not requested.
- Keep every changed line traceable to the user request.

## Phased Development
- Keep the full roadmap in view in every phase, not just the current task.
- Before building, classify each decision as foundational or local.
- Foundational decisions — schemas, storage formats, public interfaces, module and directory structure, core abstractions, dependency and version choices — are ones later phases depend on. Choose what they can extend without a rewrite.
- Local decisions are contained in this phase and cheap to swap. Keep them minimal.
- Decision test: "Would the simplest version now force a later phase to rewrite or work around it?" If yes, treat it as foundational and design for the roadmap. If no, keep it simple.
- This refines Simplicity rather than contradicting it: build only the features the current phase needs and leave future features unbuilt, but still get the foundational interfaces right.
- When the simplest path for this phase would block or complicate a later one, stop and flag it. Name the conflict, propose the alternative, give cost-now versus rewrite-cost-later, and let the user choose.

## Constraints And Dependencies
- Treat explicit prompt instructions and anything marked `confirmed limitation`, including a deliberately pinned version, as hard requirements. Follow them.
- Treat unmarked documented constraints and the project's current dependency versions as defaults, not fixed givens.
- When a different choice would materially help the current phase or roadmap — an end-of-life runtime, a setting that blocks a roadmap requirement, or a newer library version with a feature you would otherwise hand-build or work around — raise it before implementing the workaround. State what is limiting us, what the change unlocks, and its rough cost and risk, then let the user choose.
- Trigger only on a concrete benefit tied to what we are building. Leave routine upgrades alone and follow ordinary choices without comment.

## Surgical Changes
- Touch only the files needed for the task.
- Match the existing style even if you would normally write it differently.
- Do not refactor adjacent code or delete unrelated dead code unless asked.
- Preserve user changes and never revert work you did not make without explicit approval.

## Code Safety
- Fix root causes. Do not hide errors with broad try/catch, sleeps, ignored type errors, or placeholder returns.
- Do not submit TODO, FIXME, placeholder comments, mock implementations, or incomplete code unless the user explicitly asks for a draft.
- Before creating a new helper, schema, builder, or utility, search for an existing implementation and reuse it when appropriate.

## Verification
- Define success criteria before changing code.
- Run the smallest relevant validation command after changes.
- If validation cannot be run, explain why and describe the remaining risk.

## Additional Reference
## Voce — project specifics

Voce is a native macOS push-to-talk dictation app (menu-bar, no Dock icon): hold a hotkey → speak → polished text is inserted at the cursor in any app.

**Stack:** Swift 6 + SwiftUI with AppKit interop; macOS 26+, Apple Silicon first; XcodeGen-managed Xcode project → notarized DMG. **macOS only** — no cross-platform code (Windows support from the old prototype is intentionally dropped).

**This is a rewrite.** The earlier Rust/egui prototype at `../duper-disper` is REFERENCE ONLY:
- DO port the *domain logic* (audio math, refinement prompt, OpenAI Realtime protocol shape, macOS Accessibility/CGWindow patterns) — see `docs/PORTING.md`.
- DO NOT replicate its architecture (egui, subprocess windows, polling main loop, blocking calls) — see `docs/STRATEGY.md`.
- Its code was AI-generated and untested; treat behavior as unverified until confirmed against real APIs.

**Known landmine:** the prototype's default OpenAI Realtime STT backend is likely broken (wrong `session.update` schema, non-existent model id). Verify the *current* OpenAI Realtime transcription API before building the dictation loop. See `docs/PORTING.md`.

**Project docs:** `docs/STRATEGY.md`, `docs/REQUIREMENTS.md`, `docs/PLAN.md`, `docs/PORTING.md`.
