# Rewrite (macOS) — handoff brief

You are picking up an in-progress redesign of a macOS menu-bar app. Read this
whole file before touching code. It encodes decisions and failures that already
cost several days; re-deriving them wastes the user's time.

---

## 1. The app

**Rewrite** — a macOS menu-bar AI writing assistant. Swift / SwiftUI + AppKit,
deployment target macOS 14.0, `SWIFT_VERSION = 5.0`. It is a menu-bar agent
(`LSUIElement = true`) and **must stay `.accessory`** (see trap 2).

Two surfaces, one shared brain:

- **Quick surface** — clicking the menu-bar ✦ (or a hotkey) shows a floating
  panel over whatever app you're in. Paste/type/dictate text, pick an action
  (Smart, Paraphrase, Fix Grammar, …), get a rewrite. **This is the core
  product; it must work over every app and every Space.**
- **Window** — a ChatGPT-style resizable window with a conversations sidebar.
- **Modes** — Writing and Prompt, each with its own actions and separate threads.
- **In-place rewrite** — a global hotkey rewrites the current selection in any
  app via the Accessibility API.

Repo: `uxvic/rewrite`. Work branch: `claude/kind-brahmagupta-nii3ih`.
`main` is the release line.

---

## 2. State right now

| | |
|---|---|
| Live to users | **v1.8.0**, on `main` (`1ad336f`). Sparkle appcast verified live. |
| Work branch head | `cd073d9` on `claude/kind-brahmagupta-nii3ih`. CI green. |
| Unreleased on branch | popover behaviour fixes, unified conversation store, the glass redesign, plus a Windows/WPF port (separate track, never released) |

### ⚠ Decide this first: there is a live regression that is already fixed

**v1.8.0 shipped a bug that every user has right now.** It promotes the app to
a `.regular` Dock app whenever the main window is open. A `.regular` app owns a
Space, so clicking the menu-bar icon activates the app and **switches the user
to the desktop** instead of floating the popover over their current app.

The fix is commit `1d7121a`, on the branch, confirmed working on-device. It was
never released because the glass redesign piled on top of it.

**Ask the user whether to cut a 1.8.1 containing only the behavioural fixes**
(`019f397`, `1d7121a`, `77b47b4`, `d401774`) overlaid onto `main`, rather than
making users wait for the redesign to finish. Don't do it without his say-so.

---

## 3. What the redesign must be

The user supplied reference screenshots of the **"Hoy for Mac"** app and wants
that treatment in Rewrite's own identity. These are requirements, not
suggestions — he has pushed back hard when they slipped:

1. **No background at all.** No window chrome, no panel. Only floating glass
   elements over the desktop.
2. **Glassy BLACK** — piano-black, near-solid, with a glossy top sheen. Not
   charcoal, not frosted grey. He rejected this ~4 times; take it literally.
3. **Every element is its own glass** with a soft lift shadow: each bubble, the
   composer card, the mode tab.
4. **Opens directly under the menu-bar icon** — no gap ("basin") above content.
5. **Writing/Prompt tab at the TOP** of the chat. (He asked for bottom earlier,
   then reversed. Top is current.)
6. **The greeting is a chat bubble**, not a centred empty-state card.
7. **Nothing may look cropped** — no hard rectangular edge clipping shadows.
8. **Must separate from any desktop**, light or dark.
9. **Dictation is ONE glowing card** — no strands animation, no separate top
   glow. Waveform, live transcript, trash+`Esc`, violet `⏎ Use`.
10. **Use Apple's real Liquid Glass** (`.glassEffect`) on macOS 26+, with a
    fallback below that.

He works visually, iterates from screenshots, and is blunt. Study his images
before changing code — several rounds were lost guessing at his intent.

---

## 4. Architecture map

- **`RewriteApp/AppDelegate.swift`** — `NSPopover` is **gone** (it always paints
  its own frame, so "no background" was impossible). The quick surface is a
  borderless, fully transparent `FloatingPanel` (424×700) anchored under the
  status item, `backgroundColor = .clear`, `hasShadow = false` (each element
  draws its own shadow). Tear-off machinery deleted — the surface *is* a
  floating panel. Also sets `appearance = .darkAqua` on the panel.
- **`RewriteApp/DesignSystem.swift`** — `liquidGlass()` is the **single knob for
  the entire look**. macOS 26+: real `.glassEffect()` over a near-solid black
  backing. Below: near-solid black fill. Both get gloss sheen + rim + shadow.
  Depth and gloss are one number each.
- **`RewriteApp/PopoverView.swift`** — the quick surface content: thread,
  composer card, mode tab, Chats panel, `SubmitKeyMonitor`, `ComposerTextView`.
  Thread is top-anchored and content-sized (cap 430pt, then scrolls with a top
  fade); height measured via `ThreadHeightKey`.
- **`RewriteApp/VoiceOverlayView.swift`** — the dictation card.
- **`RewriteApp/Conversation.swift`** — `ConversationStore.shared`, one store
  behind **both** surfaces so chats sync. Ephemeral cards (What's New, provider
  setup) are never persisted.
- **`RewriteApp/MainWindowView.swift` / `ChatEngine.swift`** — the window.

---

## 5. Traps — all found the hard way

1. **Materials render as a light grey haze in a transparent window.**
   `.ultraThinMaterial` has nothing to sample when the window is fully
   transparent, so it paints a flat pale film. Stacking black over it converges
   on charcoal, **never black** — this one misunderstanding caused four rounds
   of "it's still not black enough". The body fill is now direct near-solid
   black; do not reintroduce a material behind it.
2. **A `.regular` activation policy owns a Space** → the menu-bar icon yanks the
   user to the desktop. Keep the app `.accessory` always. (This is the live bug.)
3. **`.mask` clips to the view's bounds, including shadows.** The thread's fade
   mask cropped bubble shadows into a hard rectangle, which read as the UI being
   "cropped in a box". Masks are padded 80pt past bounds and only applied when a
   fade is actually needed.
4. **`orderOut` does not re-fire SwiftUI's `onAppear`.** Unlike NSPopover (which
   detached content on close), hiding the panel leaves the hosting view
   attached, so clipboard auto-fill and What's New ran only once per launch. The
   host now posts `rewritePanelWillShow` on every open.
5. **`addLocalMonitorForEvents` is app-wide, not window-local.** Both the
   popover and the window have a composer, so each installs a Return-key monitor
   and could fire the *other* surface's send. Each monitor checks
   `event.window === hostView.window`. Any new monitor must do the same.
6. **NSTextView swallows `Esc` into word-completion.** The composer holds first
   responder on every show, so `.onExitCommand` never fired.
   `ComposerNSTextView.cancelOperation` posts the close notification instead.

---

## 6. Open items (none block building)

- **SHIP** — release the popover behaviour fixes (§2). Users are affected today.
- **UX** — the transparent panel swallows clicks on its shadow/glow pixels
  (click-through is per-pixel alpha). Tighten the hit area if it annoys in use.
- **VERIFY** — the macOS 26 `.glassEffect` branch has never been seen on-device;
  only the fallback path has been tested. Needs a Tahoe machine.
- **BUG (pre-existing)** — a cancelled run can clear `isLoading` for the run that
  replaced it, so Stop reverts to Send mid-stream. Fix with a generation counter
  in `run()` / `streamBody`.
- **TIDY** — `StrandsView.swift` is dead code (dictation no longer renders it).
- **TIDY** — `IconButton` still nests a material circle on the composer's glass,
  inconsistent with the chips (deliberately flat translucent).

---

## 7. Build and test

**You are running on the user's Mac, so you can build and actually look at the
result. Do that before claiming anything works** — the previous agent had no Mac
and had to rely on the user for every visual check, which was the main
bottleneck. Verify visually yourself, then hand him something already checked.

```bash
# Quit the running Rewrite first: menu-bar ✦ → right-click → Quit
cd ~/RewriteApp
git checkout claude/kind-brahmagupta-nii3ih
git pull origin claude/kind-brahmagupta-nii3ih

rm -rf build/Dev
xcodebuild -project RewriteApp.xcodeproj -scheme Rewrite -configuration Debug \
  -derivedDataPath build/Dev CODE_SIGNING_ALLOWED=NO -quiet build
codesign --force --deep --sign - build/Dev/Build/Products/Debug/Rewrite.app
rm -rf /Applications/Rewrite.app
cp -R build/Dev/Build/Products/Debug/Rewrite.app /Applications/
rm -rf build/Dev
open /Applications/Rewrite.app
```

Use `-scheme`, not `-target` — `-derivedDataPath` requires a scheme. The final
`rm -rf build/Dev` matters: every build otherwise leaves a copy that Spotlight
indexes, and duplicate "Rewrite" entries have bitten him repeatedly. If they
pile up, delete every copy except `/Applications`, rebuild the LaunchServices
database, then `killall Dock`.

`.github/workflows/macos-build.yml` compile-checks every push to the branch.

---

## 8. Releasing

Work lands on the branch, is overlaid onto `main`, then `release.sh` builds and
signs. It refuses to run on a dirty or behind checkout and bumps `Info.plist`
itself.

```bash
./release.sh 1.8.1
gh release create v1.8.1 dist/sparkle/Rewrite-1.8.1.zip dist/Rewrite.dmg \
  --title "Rewrite 1.8.1" --notes "…"

# THE STEP THAT GETS MISSED — without it nobody updates:
git add appcast.xml version.json RewriteApp/Info.plist
git commit -m "Release 1.8.1"
git push origin main
```

**Sparkle reads `appcast.xml` on `main`, not the GitHub release list.** This was
missed on 1.7.2 and nearly missed on 1.8.0 — binaries were published while the
feed still advertised the old version, so nobody received the update. Afterwards
verify the appcast's version, download URL and byte length match the uploaded
zip.

---

## 9. Working agreements

- **Never push to `main` without explicit permission.** "Ship it" / "push to
  users" counts; nothing else does.
- **Do not open pull requests** unless asked.
- **Never put a model identifier** in commits, PR text, code comments, or
  anything else pushed to the repo.
- **Test builds stay on the feature branch.** He tests, then decides what ships.
- The previous agent's commits carry a `Co-Authored-By: Claude …` /
  `Claude-Session:` footer. **Do not copy that footer** — it is specific to that
  agent. Write plain commit messages.
- Ask when his intent is genuinely ambiguous, but don't stall on things he has
  already answered.
