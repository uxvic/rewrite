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
- [ ] Redesign the quick menu-bar Rewrite surface.
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
