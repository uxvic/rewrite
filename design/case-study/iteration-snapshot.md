# Rewrite — Iteration Snapshot

> Raw material for a future writing case study. Captured 2026-06-29.
> This is a working log, not the finished piece: the facts, the decisions, the
> friction, and the user's own words — kept honest so the polished case study
> can be built on something real rather than reconstructed from memory.

---

## 1. What Rewrite is

A macOS menu-bar AI writing assistant. You select text anywhere (or type, paste,
or dictate it), and Rewrite rewrites it — fix grammar, change tone, paraphrase,
shorten, or run it through a "Prompt" mode that turns a rough prompt into a
well-engineered one. It runs as a background agent (`LSUIElement`), opens from a
hotkey or the menu bar, and streams results into a chat-style UI. It can run fully
on-device (Apple's on-device model, free, private), through free hosted models, a
local Ollama, a Claude API key, or a Claude Code subscription.

The product thesis: **the fastest possible distance between "this text isn't right"
and "this text is right" — without leaving the app you're in.**

---

## 2. The arc of the story (the through-line)

The interesting thing about this stretch of iteration is *who found the problems*:
the designer was also the daily user. Almost every release in this window started
not with a roadmap but with a moment of friction in real use — "I paused while
dictating and it erased my sentence," "I clicked away and my voice session
vanished," "white text on lavender is unreadable." Dogfooding set the agenda.

The arc moves through three phases:

1. **Make the surface feel right** (1.2–1.4): the chat composer, voice capture, the
   send-then-pick-a-style interaction, in-chat model setup.
2. **Make it trustworthy** (1.5.x): stop it from quietly losing the user's work
   (dictation), stop modes from bleeding into each other, stop prompts from leaking
   their own instructions.
3. **Make it feel like a tool you own** (1.6.x → Smart): tear the window off the
   menu bar and put it anywhere; keep a voice session alive across spaces; and
   finally, make a plain "send" *understand intent* instead of blindly rewriting.

The emotional register shifts from "does it look good" to "does it respect my
work" to "does it understand what I meant."

---

## 3. Timeline (the facts)

| Version | Date | What shipped | The "why" behind it |
|---|---|---|---|
| 1.0.0 | early Jun | Consumer-ready menu-bar rewriter | The seed: rewrite-not-answer, output under input, recording feedback. |
| 1.1.0 | Jun | Sparkle silent auto-update | Ship fixes without asking users to re-download. |
| 1.2.0 | Jun 5 | Prompt mode, clipboard auto-fill, Regenerate, grammar Diff | Two jobs in one tool: writing *and* prompt-engineering. |
| 1.2.1–1.2.2 | Jun 5 | First-click + tab hit-target fixes | A menu-bar popover swallows the first click; controls felt dead. |
| 1.2.3 | Jun 8 | Dictation input auto-scrolls | Long dictation scrolled the latest words out of view. |
| 1.3.0 | Jun 8 | Full-takeover voice UI (reactive orb + waveform) | Voice deserved its own focused moment, not a cramped field. |
| 1.3.1 | Jun 8 | Live transcript auto-scrolls | Same problem, the voice screen's turn. |
| 1.4.0 | Jun 21 | Chat UI redesign, in-chat model setup, What's New, typing indicator | The composer becomes a conversation; setup happens where you hit the wall, not in a settings maze. |
| 1.4.1–1.4.2 | Jun 21 | Popover closes on click-away; refreshed icon | Basic "it behaves like a popover should." |
| 1.5.0 | Jun 22 | Separate Writing/Prompt threads + history; default-rewrite on send; App-Store-readiness (privacy manifest, account deletion); What's New moved *into the chat* | Modes shouldn't share one muddled thread; sending with no style picked should still do the obvious thing; release notes should be seen, not buried behind a banner. |
| 1.5.1 | Jun 22 | History gets its own Writing/Prompt tab; fixed Prompt mode echoing its own instructions | A real leak: the prompt-optimizer was restating its rules into the output. |
| 1.5.2 | Jun 27 | First attempt at the dictation pause-clear fix | **Wrong fix** — see §4.1. |
| 1.5.3 | Jun 27 | Proper dictation fix: detect the recognizer's in-place reset | Root-caused and verified before shipping. |
| 1.6.0 | Jun 27 | Draggable tear-off window; persistent voice across spaces; header gear→close (✕); Settings moved to the menu-bar menu | "Let me put it where I want it, and don't let it disappear on me." |
| 1.6.1 | Jun 27 | Removed What's New "Try it" button; fixed white-on-lavender contrast; close ✕ on the voice screen | Accessibility + small dignity fixes. |
| **Smart** | (pending) | Intent-aware send: classify *rewrite vs. fulfill a request*, then act | Make a plain send *understand* what the user wants — polish text, or actually produce the thing they asked for. |

---

## 4. The case-study-worthy moments (the vignettes with real tension)

These are the four or five beats that will carry the actual case study. Each has a
clean problem → insight → decision → outcome shape.

### 4.1 "I paused, and it erased my sentence" — the bug that took two tries

**The report (the designer, as a user):** *"Whenever I'm recording my voice, if I
pause for about five seconds, it clears what I've already dictated. It should just
add to it — unless the user decides to clear it."*

**First fix (1.5.2) — wrong.** The obvious theory: the speech recognizer fires a
"final" result on a pause, so accumulate text only when `result.isFinal`. Shipped
it. It didn't work — because Apple's **on-device** recognizer never sets `isFinal`
on a pause. The assumption was about the cloud recognizer; the app runs on-device.

**The real root cause (1.5.3).** On-device recognition doesn't end a segment on a
pause — it *silently resets `formattedString` in place* and starts the next phrase
over from scratch. From the outside it looks like the transcript "jumped back." The
fix wasn't a flag; it was learning to recognize the reset: a **word-overlap
heuristic** that detects when the new partial no longer extends the old one, plus a
**generation guard** so a stale callback can't overwrite freshly committed text.
The committed transcript is folded forward; nothing is ever silently dropped.

**Why it matters for the case study:** this is the "respect the user's work" beat.
The lesson is about *the danger of a plausible fix*. The first version was
reasonable, testable, and wrong — and the only reason the second one was right is
that the failure was reproduced and the recognizer's actual behavior was observed
rather than assumed. (A structured root-cause-then-verify pass caught it before it
shipped a second time.)

> **Pull quote:** "It should just add to it — unless the user decides to clear it."
> One sentence that encodes a whole principle: *never destroy input the user didn't
> ask you to destroy.*

### 4.2 "Let me put it where I want it" — the tear-off window

**The ask:** *"When I click on Rewrite in my menu bar, I want to be able to drag it
and put it anywhere. I don't want us to change the UI — I just want the
functionality. If they don't drag it out, the chat can stay non-persistent."*

**The tension:** a menu-bar popover (with its little arrow anchored to the icon) and
a free-floating, draggable window are *technically different objects* in macOS
(`NSPopover` vs. `NSPanel`). The naive path is to replace one with the other — but
that throws away the docked, arrow-anchored feel the user explicitly said to keep.

**The decision — a hybrid tear-off.** Keep the docked `NSPopover` exactly as-is.
The moment you *drag* the header (or activate voice), detach into a borderless
floating `NSPanel` that lives above other windows, joins all Spaces, and survives
clicking away and app-switching. The same SwiftUI view (and its in-progress state)
is *moved* between the two containers, so nothing resets when it tears off.

**What adversarial review caught before shipping:**
- A local event monitor wouldn't receive drag events once the popover's own window
  closed → switched to a 120 Hz cursor-position poll to follow the drag.
- Reparenting the view fired `onDisappear`, which was wired to stop the mic — it
  would have killed a just-started recording. Removed it; the mic now stops only on
  an explicit Done/Cancel/redock.
- Positioning the torn-off panel by the popover's window frame caused a visible
  jump → position by the content rect instead.

**Outcome:** docked when you want quick, floating-and-persistent when you want to
keep it around — and the look never changed, exactly as asked.

**Case-study beat:** *constraint as a design gift.* "Don't change the UI, add the
capability" forced a more elegant answer (two containers, one view) than a redesign
would have.

### 4.3 "White on the purple isn't accessible" — the small dignity fix (1.6.1)

The accent lavender with white text failed contrast. Fixed with a **dynamic ink
color** — white-ish on the accent in dark mode, near-black in light mode — so the
selected chips and pills stay legible in both appearances. Tiny diff, real
inclusion. Good case-study material precisely *because* it's small: it shows the
practice of treating accessibility as a bug, not a nice-to-have.

### 4.4 "What's new, right here" — release notes that land in the conversation

Earlier, updates surfaced as a slim banner the user had to notice and click.
Decision: when you update, drop the **full What's New card straight into the chat
thread**, top of the conversation, the next time you open it — and refresh the tour
copy every feature release. The insight: in a chat-shaped product, the chat *is* the
place attention already lives. Don't build a second surface to compete with it.

### 4.5 "Be intelligent about what I meant" — the Smart send (the latest beat)

**The ask:** *"I want the app to understand when I'm giving it text to rewrite and
when I'm asking it for something. If I say 'help me draft an email,' it should know
that's a request — not a sentence to paraphrase — and actually draft it."*

**The problem with the old model:** every input was treated as *text to rewrite*.
The prompts literally said "never answer it." So "help me draft an email telling Ada
we'll hit our limit" got *paraphrased* — "Could you help me draft an email…" —
instead of fulfilled. The tool was being obedient in the dumbest possible way.

**The shape we chose (user's call, via two quick decisions):**
- **On by default, with a visible toggle.** A "Smart" chip in the Writing action bar
  (and a Settings switch) — intelligence is the default, but the user keeps the
  wheel. *"The button is just to give the user control."*
- **Classify, then act.** A tiny first pass labels the input `REWRITE` or `REQUEST`
  (one word, defaulting to `REWRITE` when unsure), then routes:
  - `REQUEST` → a writing-*assistant* prompt that actually produces the asked-for
    text, paste-ready.
  - `REWRITE` → the existing light-polish path, unchanged.

**Deliberate safety boundaries (these are the interesting design constraints):**
- Scope is **Writing mode's plain send only.** Explicit styles (Paraphrase, Fix
  Grammar…), custom instructions, and Prompt mode stay literal rewrites — picking a
  style is an explicit "I know what I want."
- Classification **fails safe**: any error, any ambiguity, any cancel → it rewrites.
  Smart can never do *less* than the old default send. The new "answer the request"
  capability — the one place the "never answer it" guard is relaxed — only opens for
  plain sends the classifier is confident are requests.
- Request results don't pretend to be rewrites: they aren't re-wrapped on retry, and
  the source/result **Diff** (meaningless for "request → drafted email") is hidden.

**Case-study beat:** *intelligence as restraint.* The hard part wasn't adding a
classifier — it was drawing the box small enough that the feature can't surprise
you. Default-on, but provably never worse than before.

---

## 5. Cross-cutting principles that emerged (the case study's spine)

1. **Never destroy the user's input silently.** (Dictation.) If something gets
   cleared, the user asked for it.
2. **Constraints sharpen design.** "Don't change the UI, add the capability"
   produced the two-containers-one-view tear-off — cleaner than a redesign.
3. **Default to intelligent, but always hand over the wheel.** Smart is on by
   default *and* toggleable. Auto-fill, auto-copy, persistence — same pattern.
4. **Fail safe, then fail visible.** Classifier can't reach? Rewrite. Provider not
   set up? Inline setup card, not a raw error.
5. **Meet attention where it already is.** What's New goes into the chat; setup
   happens at the wall you hit, not in a separate settings journey.
6. **Distrust the plausible fix.** Reproduce the failure and watch the real
   behavior before shipping (the two-attempt dictation fix is the cautionary tale).
7. **Accessibility is a bug class, not a polish phase.** The contrast fix shipped as
   a fix, with the same urgency as a crash.

---

## 6. Artifacts to gather for the polished case study

- **Before/after screen recordings:** dictation pause (erase vs. accumulate);
  docked popover → drag → floating panel; "help me draft an email" sent with Smart
  off (paraphrased) vs. Smart on (drafted).
- **The two dictation diffs** side by side (1.5.2 wrong fix vs. 1.5.3 real fix) —
  the strongest single artifact in the whole story.
- **The Smart decision moments:** the two choices the user made (on-by-default +
  toggle; classify-then-act) — show that the user, not the tool, set the policy.
- **Contrast before/after** in light and dark.
- **The What's New card** in the thread.
- **Stats:** ~16 releases across this window, several driven directly by a single
  sentence of real-use friction. The cadence itself is a story (four releases in one
  day — 1.5.2/1.5.3/1.6.0/1.6.1 on Jun 27 — is the "ship the moment it's right"
  rhythm).

---

## 7. The user's own words (verbatim-ish — gold for a case study)

- *"It should just add to it — unless the user decides to clear it."* (dictation)
- *"I don't want us to change the UI, but I want it to have that functionality where
  you can just drag it and put it on any location."* (tear-off)
- *"If they mistakenly click outside, it disappears… it should be persistent. Even if
  they switch to another screen."* (persistent voice)
- *"The white on the purple is not accessible."* (contrast)
- *"I want the application to be very intelligent… it should determine: this is a
  request, not just a rewrite."* (Smart)
- *"Auto, plus a smart button — on by default, but the button is just to give the
  user control."* (the Smart policy decision)

Each quote is a design requirement compressed to one line. The case study can hang a
section on each.

---

## 8. Open threads / what's next

- **Ship Smart as a release.** It's a feature, so it warrants a feature-version bump
  (≈1.7.0), which re-shows the What's New tour — the tour copy will need a fresh
  entry describing intent-aware send. (Awaiting the go-ahead before releasing.)
- **Possible future beats:** per-language request handling; a way to nudge a
  borderline classification ("treat this as a request"); surfacing *why* Smart chose
  a path.
- **The redesign track:** a full "Rewrite Redesign" Figma file is staged as runnable
  scripts (`design/figma/`), a parallel thread to this functional iteration.

---

*Maintainer note: keep this honest. The value of this snapshot is that it records
the wrong turns (the 1.5.2 dictation fix) and the constraints, not just the wins. A
case study built only from the highlights reads like marketing; this one can read
like the real thing.*
