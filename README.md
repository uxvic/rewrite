<div align="center">

# ✦ Rewrite

**A private writing assistant that lives in your Mac's menu bar.**
Paraphrase, fix grammar, change tone, or rewrite selected text anywhere — powered by Apple's
on-device AI out of the box, with no account or API key required.

[**⬇ Download for Mac**](https://github.com/uxvic/rewrite/releases/latest/download/Rewrite.dmg) · [Website](https://uxvic.github.io/rewrite/) · [Privacy](PRIVACY.md)

</div>

---

## What it does
- **Paraphrase, Fix Grammar, Shorter, Longer, Professional, Casual, Friendly** — plus your own custom presets.
- **Rewrite selected text in any app** — select text, press ⌥⇧Space, it's rewritten in place.
- **Dictate** instead of typing (on-device speech).
- **Streaming** results, history, and one-tap copy.
- Open it with the menu-bar icon or **⌥Space** from anywhere.

## Works out of the box — no setup
By default Rewrite uses **Apple's built-in on-device model** (macOS 26, Apple Silicon): free, private,
offline, nothing to configure. Prefer something else? In **Settings** you can switch to:

| Engine | Setup | Notes |
|---|---|---|
| **Built-in AI** (default) | none | On-device, free, private. macOS 26 + Apple Silicon. |
| **Free models (newsletter)** | email sign-in | Hosted by the maintainer; gated behind a newsletter signup. |
| **Open-source local (Ollama)** | install Ollama | Run Llama/Qwen/etc. fully locally. |
| **Claude (API)** | your API key | Highest quality; pay-as-you-go. |

## Install
1. **[Download Rewrite.dmg](https://github.com/uxvic/rewrite/releases/latest/download/Rewrite.dmg)**, open it, drag **Rewrite** to **Applications**.
2. First launch: because the app isn't yet notarized, macOS may warn it "cannot be verified."
   **Right-click the app → Open → Open** (or System Settings → Privacy & Security → **Open Anyway**).
3. The welcome screen shows you the hotkeys and optional permissions (Accessibility for in-place
   rewrite, Microphone for dictation).

> Requires macOS 14+. The zero-setup built-in AI needs macOS 26 + Apple Silicon with Apple Intelligence on;
> on other Macs, pick another engine in Settings.

## Build from source
```bash
git clone https://github.com/uxvic/rewrite.git
cd rewrite
open RewriteApp.xcodeproj   # ⌘R in Xcode (Xcode 26+)
```
The optional hosted "Free models" backend lives in [`gateway/`](gateway/) (Cloudflare Worker) — see its README.

## License
[MIT](LICENSE) © 2026 Victor Adedini
