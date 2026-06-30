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

## The other batches
Each is a standalone script that draws onto the **same** "Rewrite — Full UI" page (offset
to the right/below Batch 1), is **idempotent** (removes only its own prefixed frames on
re-run), and `figma.notify`s when done. Run them in any order; running all four gives the
full set. Same run method as Batch 1 — point a local Claude Code at each file via `use_figma`
against fileKey `e38OAw7xSAHMYhZksDIwjY`.

- **`rewrite_redesign_batch2.js`** — remaining chat states (`Chat2 ·`): empty (Writing/Prompt),
  assistant **typing**, **Diff** (accent additions / red-strikethrough removals), **error**,
  **Setup card** (provider radio list + email sign-in), and **History** with the new 1.5.1
  Writing|Prompt tab.
- **`rewrite_redesign_batch3.js`** — Settings (`Set3 ·`): a full Claude/Anthropic window
  (Provider radios → Connection → API steps → General toggles/hotkeys → Custom Presets →
  Updates → Privacy), plus per-provider variants (Free models signed-out & signed-in+delete,
  Built-in AI, Claude Code, Ollama).
- **`rewrite_redesign_batch4.js`** — Voice + Welcome (`VW4 ·`): Voice overlay (Listening /
  Transcribing) with the strands approximated as blurred lavender ribbons + the 24-bar
  waveform pill, and the Welcome window (460×560) in permissions-needed and all-granted states.

Suggested order: run Batch 1, eyeball it, then 2 → 3 → 4. All scripts are parse-checked
(`node --check`). Icons are monoline SF-Symbol approximations; the live voice shader is a
static stand-in.
