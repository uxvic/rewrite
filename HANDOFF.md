# Rewrite redesign handoff

Working branch: `rewrite`

Owner: CODEX

## Plan

- [x] Preserve the earlier Codex rewrite implementation on a recoverable remote branch.
- [x] Adopt Claude's floating-panel implementation as the `rewrite` baseline.
- [x] Verify the adopted app and retained main window build and launch cleanly.
- [ ] Verify the floating quick surface directly under the menu-bar icon.
- [ ] Reintroduce one unified Rewrite flow without compromising the floating composition.
- [ ] Integrate private, local Clipboard History as a separate destination.
- [ ] Tune the visual hierarchy against the supplied Apple Liquid Glass references.
- [ ] Add focused accessibility and interaction verification, then prepare a review checkpoint.

## Log

### 2026-08-31 — CODEX

- Victor selected Claude's floating implementation as the design baseline after comparing the previous attempt.
- The prior Codex implementation, including the unified Rewrite mode and local Clipboard History work, is preserved remotely at `codex/rewrite-before-claude-baseline` (`c51d029`). It is a recovery/reference branch, not the active UI baseline.
- `rewrite` now starts from `783fc5e` on `origin/claude/kind-brahmagupta-nii3ih`, which contains the transparent AppKit floating-panel host, black Liquid Glass treatment, and retained main window.
- Next: restore the local build entrypoint and verify a clean unsigned Debug build before porting features back one at a time.
- No files are reserved for Claude. Owner remains CODEX.

### 2026-08-31 — CODEX — commit `7f390ff`

- Officially moved the shared `rewrite` branch to Claude's floating-panel baseline and added this root `HANDOFF.md` for the required Git-only collaboration flow.
- Files: `HANDOFF.md`. The branch update was protected with `--force-with-lease`; the former `rewrite` tip remains available on `codex/rewrite-before-claude-baseline`.
- Next: restore `script/build_and_run.sh` and the local Run environment from the preserved work, then verify the adopted baseline builds before changing product UI or clipboard code.
- No files are reserved for Claude. Owner remains CODEX.

### 2026-08-31 — CODEX — commit `2ba153a`

- Restored the project-local Debug build/run entrypoint from the preserved branch without changing application behaviour.
- Files: `script/build_and_run.sh`, `.codex/environments/environment.toml`.
- Next: run the adopted Claude baseline through an unsigned Debug build and verify its output before integrating any features from the preserved implementation.
- No files are reserved for Claude. Owner remains CODEX.

### 2026-08-31 — CODEX — verification checkpoint

- `./script/build_and_run.sh --verify` completed successfully against the adopted baseline. The unsigned Debug bundle built and launched from `work/DerivedData`.
- The retained main window was inspected through macOS accessibility output. The menu-bar-only floating panel is not exposed by that inspector, so its exact open/close geometry still needs direct status-item verification before any visual claims.
- Next: manually port the unified Rewrite model without importing old quick-surface layout code, then add Clipboard History data capture as a separate bounded feature.
- No files are reserved for Claude. Owner remains CODEX.
