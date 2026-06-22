# Rewrite Redesign — Figma build scripts

High-fidelity redraw of the Rewrite app UI, authored straight into Figma via the
Figma MCP `use_figma` tool (Figma Plugin API). The scripts reconstruct each screen
from the SwiftUI source — `Inter` substitutes for SF Pro, and icons are monoline
SVG approximations of SF Symbols. Colors and radii are the app's real `Theme` /
`Metric` tokens (`RewriteApp/DesignSystem.swift`).

**Target Figma file:** **Rewrite Redesign** (Moniepoint org)
- URL: https://www.figma.com/design/e38OAw7xSAHMYhZksDIwjY
- `fileKey`: `e38OAw7xSAHMYhZksDIwjY`

## Why these scripts exist
The remote/web Claude Code session can read Figma and created this file, but the
`use_figma` *write* tool is gated by the Figma MCP gateway and the approval never
surfaced in that remote session. Running it from a **local Claude Code on a Mac**
surfaces the normal Allow prompt, so the redraw goes through there.

## Run it (local Claude Code, ~2 min)
1. Add the Figma MCP to Claude Code (one-time):
   ```bash
   claude mcp add --transport http figma https://mcp.figma.com/mcp
   # or: claude plugin install figma@claude-plugins-official
   ```
   Authenticate as the Figma account with edit access to the Moniepoint org
   (victor.adedini@moniepoint.com).
2. From this repo on your Mac, start `claude` and ask:
   > Run the code in `design/figma/rewrite_redesign_batch1.js` via the Figma
   > `use_figma` tool against fileKey `e38OAw7xSAHMYhZksDIwjY`.
3. **Approve the Allow/Approve prompt** when it appears. The page
   "Rewrite — Full UI" gets a color-foundations strip and the hero 380×668
   popover frame.

### Alternative: run as a Figma dev plugin
Create a quick dev plugin (Figma → Plugins → Development → New plugin…), paste the
file's IIFE body into `code.js`, and run it on the open file. Same result.

## What Batch 1 builds
- Page **"Rewrite — Full UI"** (dark showcase) + a header note.
- **Foundations · Color** — the eight Theme swatches with hex labels.
- **Chat · What's New in chat (1.5.0)** — 380×668 popover: header (history /
  Writing·Prompt pill / settings), the restored **in-chat What's New card** with
  the 1.5.0 tour copy, a user + assistant turn (Copy/Use/Retry/Diff), and the
  composer (inside send button + Paraphrase/Fix Grammar/Shorter/Longer chips + mic).

The script is **idempotent** — re-running removes its own previously-created nodes
first, so it won't pile up duplicates.

## Remaining batches (to be added)
- **Batch 2** — remaining chat states: empty, "pick a style" nudge, typing, diff,
  error, Setup-card variants, History (empty / with items).
- **Batch 3** — Settings frames (per-provider blocks + General / Custom Presets /
  Updates / Privacy).
- **Batch 4** — Voice overlay (Listening / Transcribing) + Welcome window (460×560).

Run Batch 1 first and confirm it looks right; the same patterns/helpers carry into
2–4 (they can be generated the same way).
