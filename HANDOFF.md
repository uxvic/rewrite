# Rewrite redesign handoff

Working branch: `rewrite`

Owner: CODEX

## Plan

- [x] Audit the existing Rewrite macOS, Windows, gateway, and release structure.
- [x] Review the supplied floating-composer and Siri Liquid Glass references.
- [x] Review MightyPaste as future clipboard-domain research only.
- [x] Establish adaptive Liquid Glass primitives with a macOS 14–25 fallback.
- [ ] Split the menu-bar UI into focused components without changing behaviour.
- [x] Collapse Writing and Prompt into one Rewrite flow with a safe local-data migration.
- [x] Establish Rewrite and Clipboard as separate quick-surface destinations.
- [ ] Redesign the quick menu-bar Rewrite surface.
- [ ] Build private local clipboard capture, storage, retention, and "send to Rewrite" behaviour.
- [ ] Redesign the retained main Rewrite window.
- [ ] Verify build, native interactions, accessibility, and motion; add targeted tests and repair CI triggers.

## Log

### 2026-08-31 — CODEX

- Created the dedicated `rewrite` branch from current `main`.
- Completed a read-only product and architecture audit. No application source files have changed yet.
- Reviewed the supplied reference frames and Siri screenshots as visual reference only. The direction is adaptive native glass, a persistent floating composer, and one unified Rewrite flow; it does **not** copy Siri's literal Applications/Files/Actions/Clipboard menu.
- Cloned and reviewed MightyPaste under the shared workspace as future research only. Do not port its notch UI, lifecycle, or plaintext clipboard persistence into this redesign.
- Next: create the glass foundation as the first small, buildable UI checkpoint.

### 2026-08-31 — CODEX

- Implemented the adaptive material foundation in `RewriteApp/DesignSystem.swift`.
- Added native `glassEffect` / `GlassEffectContainer` use on macOS 26+, while retaining the current material fallback for macOS 14–25. Existing `glassFloat` now routes through that compatibility layer.
- Next: build and visually inspect this checkpoint, then extract the quick-surface composer into a focused component.

### 2026-08-31 — CODEX

- Collapsed the user-facing mode model to a single `RewriteMode.rewrite` flow. Legacy `writing` and `prompt` values still decode, then canonicalize to `rewrite`, preserving existing local history and conversations.
- Added prompt optimization as an explicit unified action instead of a separate top-level tab.
- Next: remove the now-redundant segmented controls and redesign the menu-bar and main-window shells around the unified flow.

### 2026-08-31 — CODEX — commit `3b0e07d`

- Pushed the unified-mode checkpoint: `RewriteMode`, `AppSettings`, `Conversation`, and `MainWindowView` now default to one Rewrite flow; legacy persisted mode values canonicalize to it.
- Build passed with `xcodebuild -project RewriteApp.xcodeproj -scheme Rewrite -configuration Debug CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -derivedDataPath work/DerivedData build`.
- Claude review requested: check the legacy-mode decoding/migration semantics and recommend the final compact action set for the rewritten composer. Do not edit `RewriteApp/DesignSystem.swift` while reviewing; that is the shared glass foundation from commit `343443e`.
- Next owner task: propose or implement the extraction boundary for `PopoverView.swift` before its visual redesign. Commit and push your response, then set Owner=CODEX.

### 2026-08-31 — CLAUDE — review, no code changed

Reviewed `343443e` and `3b0e07d`. No application source touched; `DesignSystem.swift`
left alone as requested. Findings and answers below.

**Branch base — needs a human decision before more UI work.**
`rewrite` was cut from `main` (`1ad336f`), so it does not contain the work on
`claude/kind-brahmagupta-nii3ih`: a background-less transparent-panel menu-bar
surface, a shared `ConversationStore` used by both surfaces, and — importantly —
the fix for a regression that is live in v1.8.0 today. On this branch
`AppDelegate` still calls `setActivationPolicy(.regular)` when the main window
opens; a `.regular` app owns a Space, so clicking the menu-bar icon switches the
user to the desktop instead of floating the surface over their current app. Any
menu-bar redesign built here inherits that. Options: merge that branch in, or
cherry-pick `019f397 1d7121a 77b47b4 d401774`, or knowingly rebuild.

**Defects found in the unified-mode change (`3b0e07d`).**

1. Blocking — existing conversations disappear. `Conversation` uses synthesized
   `Codable`, so `mode` decodes straight from disk and keeps `writing`/`prompt`;
   only `AppSettings` and `HistoryItem` canonicalize. `MainWindowView` filters
   `conversations.filter { $0.mode == engine.mode }` against `.rewrite`, so every
   pre-existing chat is filtered out of the sidebar. Data is intact on disk, but
   it reads as loss. Fix in `ConversationStore.load()` (canonicalize after decode,
   then persist once) or with a custom `init(from:)` on `Conversation`.
2. Blocking — Smart's prompt-optimizing path is now unreachable.
   `ChatEngine.swift:82,122` and `PopoverView.swift:658,699` still branch on
   `mode == .prompt`, which can never be true now, so Smart always uses the
   writing prompt and silently lost half its behaviour. Decide: drop
   prompt-Smart, or route it off the selected action instead of the mode.
3. `MainWindowView.swift:55` still renders `m == .writing ? "Writing" : "Prompt"`
   over a one-element `allCases`, producing a single pill mislabelled "Prompt".
   `PopoverView` has the same shape (`modeSegmented`, and `historyMode = .writing`
   at line 66) — a one-segment segmented control.
4. Build risk — `glassEffect` / `.regular.interactive()` are guarded with
   `if #available(macOS 26.0, *)` but not `#if compiler(>=6.2)`. Without the
   macOS 26 SDK the symbols don't exist and the build fails. Your Xcode has the
   SDK; another machine or CI may not.
5. No CI on this branch — `.github/workflows/macos-build.yml` triggers only on
   `claude/kind-brahmagupta-nii3ih`. Worth repairing early, not last.
6. Minor — on macOS 26 `adaptiveGlass` drops the shadow and stroke the fallback
   applies, so floating controls lose their lift there. Fine if deliberate.
   `AppDelegate.swift:440` still logs in-place rewrites as `mode: .writing`.

No id collision between `RewriteAction` raw values and the injected `optimize`
action. The `canonical` + deprecated-case approach is otherwise sound.

**Answers to the three questions.**

*Migration semantics* — see defect 1; canonicalize on load in `ConversationStore`
and rewrite the file once, so the fix is idempotent and old data self-heals.

*Final compact action set* — the Siri reference resolves this. Actions belong in
a **list section**, not a growing chip strip. Keep at most four chips on the
composer (`✦ Smart`, `Improve`, `Paraphrase`, `Fix Grammar`) and move the rest —
Shorter, Longer, Professional, Casual, Friendly, Optimize, and user presets —
into an `Actions` section with `⌘`-numbers, mirroring
Applications/Files/Actions/Clipboard.

*PopoverView extraction boundary* — split by surface, keeping all mutable state
in the root so the pieces stay dumb and previewable:
`Popover/PopoverRoot.swift` (state + routing), `Popover/ComposerView.swift`
(field, chips, tool row, `SubmitKeyMonitor`), `Popover/ThreadView.swift`
(bubbles, streaming, retry, diff), `Popover/SectionList.swift` (new nav),
`Popover/ChatsPanel.swift`, `Popover/SetupCards.swift` (setup + What's New).
`VoiceOverlayView` is already separate. Do this refactor with **no behaviour
change** before the visual redesign — every later phase edits this file.

**Direction from the new references (macOS 26/27 Siri frames).**
The glass is *dark-leaning adaptive*: near-black over a black desktop, warm and
see-through over the photo. It darkens whatever is behind it enough for white
text, but takes hue and luminance from it. It is **not** a fixed black fill —
that was tried on the other branch and fights coloured backgrounds. Structure to
match: a rounded **composer capsule** (placeholder + trailing mic) above a
**rounded list panel** of sections with `⌘1..⌘N` right-aligned, both inside one
`GlassEffectContainer` so they refract as one material.

**Main window — settled by Victor: leave it as it is.** It stays reachable and
untouched for now; it will be redesigned later with more features, to his plan.
Treat `MainWindowView.swift` as out of scope except where a shared type forces a
compile fix (e.g. the mislabelled mode pill in defect 3).

**Suggested order** — 0: fix defects 1–5. 1: settle branch base. 2:
`PopoverView` extraction (no behaviour change). 3: adaptive glass
primitives against the Siri frames. 4: section list with `⌘`-numbers. 5: clipboard
history (capture → store → UI → "send clip to composer"), grounded in
`uxvic/MightyPaste`, with transient/concealed pasteboard types excluded from
capture on day one. 6: accessibility, motion, tests, CI.

Owner set to CODEX. Nothing is reserved by Claude; all files are free.

### 2026-08-31 — CODEX

- Cherry-picked the reviewed menu-bar regression fixes from `claude/kind-brahmagupta-nii3ih` as `1263783`, `e35c2c5`, `7ba2e05`, and `d71648b`. Rewrite now remains an accessory app, so the quick surface can appear over the current app and Space while the main window stays available.
- Fixed the unified-mode data migration in `ConversationStore.load()`; legacy conversations now self-heal to the unified mode and are persisted once. Smart now consistently uses the unified Rewrite behaviour.
- Added compiler guards around Liquid Glass symbols and repaired macOS CI branch triggers for `main` and `rewrite`.
- Build passed. Remaining known UI work: remove legacy segmented controls and extract/redesign the quick surface. Owner remains CODEX.

### 2026-08-31 — CODEX — commit `89fbfc5`

- Replaced the leftover one-option Writing/Prompt control in `RewriteApp/PopoverView.swift` with an adaptive-glass `Rewrite` / `Clipboard` destination switcher.
- Added the Clipboard empty state as a genuine separate surface, including the private-on-this-Mac product framing. It deliberately does **not** monitor or persist clipboard contents yet; that requires a separate, privacy-sensitive capture and retention design.
- Removed residual prompt-mode branches from the quick surface and corrected the in-place rewrite history tag in `RewriteApp/AppDelegate.swift` to the unified Rewrite mode.
- Build passed with `xcodebuild -project RewriteApp.xcodeproj -scheme Rewrite -configuration Debug CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -derivedDataPath work/DerivedData build`.
- Next: tighten the Rewrite composer into the four direct actions from the reference direction, move the remaining transforms behind a compact Actions menu, then continue the glass and layout pass. Owner remains CODEX.

### 2026-08-31 — CODEX — commit `c5e508c`

- Reworked the Rewrite action rail in `RewriteApp/PopoverView.swift`: Smart, Improve, Paraphrase, and Fix Grammar are the only immediate choices.
- Moved the less-frequent transforms, prompt optimization, saved presets, and custom instruction into a compact native `Actions` menu. Existing keyboard shortcuts remain assigned to the menu items.
- Applied the adaptive glass primitive to unselected action controls, so macOS 26+ gets native refraction while macOS 14–25 keeps the material fallback.
- Build passed with the standard unsigned `xcodebuild` command. Next: visually inspect the running macOS surface and tune hierarchy, spacing, and glass against the supplied reference. Owner remains CODEX.
