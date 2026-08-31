# Rewrite redesign handoff

Working branch: `rewrite`

Owner: CODEX

## Plan

- [x] Preserve the earlier Codex rewrite implementation on a recoverable remote branch.
- [x] Adopt Claude's floating-panel implementation as the `rewrite` baseline.
- [ ] Verify the adopted floating quick surface and its retained main window build cleanly.
- [ ] Reintroduce one unified Rewrite flow without compromising the floating composition.
- [ ] Integrate private, local Clipboard History as a separate destination.
- [ ] Tune the visual hierarchy against the supplied Apple Liquid Glass references.
- [ ] Add focused accessibility and interaction verification, then prepare a review checkpoint.

## Log

### 2026-08-31 — CODEX

- Victor selected Claude's floating implementation as the design baseline after comparing the previous attempt.
- The prior Codex implementation, including the unified Rewrite mode and local Clipboard History work, is preserved remotely at `codex/rewrite-before-claude-baseline` (`c51d029`). It is a recovery/reference branch, not the active UI baseline.
- `rewrite` now starts from `783fc5e` on `origin/claude/kind-brahmagupta-nii3ih`, which contains the transparent AppKit floating-panel host, black Liquid Glass treatment, and retained main window.
- Next: make the baseline official on the shared branch, restore the local build entrypoint, and verify a clean unsigned Debug build before porting features back one at a time.
- No files are reserved for Claude. Owner remains CODEX.
