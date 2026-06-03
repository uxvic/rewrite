# Privacy Policy — Rewrite

_Last updated: 2026_

Rewrite is a menu-bar writing assistant for macOS. This policy explains what happens to your data.
The short version: **by default, nothing leaves your Mac.**

## What we collect
**Nothing on a central server by default.** Rewrite has no analytics, no tracking, and no accounts
unless you opt into a provider that needs one.

## Where your text goes (depends on the engine you choose in Settings)
- **Built-in AI (default):** your text is processed **entirely on your device** by Apple's on-device
  model. It is not sent anywhere.
- **Open-source local (Ollama):** processed locally by the model running on your Mac.
- **Free models (newsletter):** to use this option you enter your email and verify a code. Your email
  is added to the maintainer's newsletter (via Kit), and the text you rewrite is sent to the maintainer's
  gateway and an upstream model provider (e.g. Google Gemini) to generate the result. The gateway stores
  only a sign-in token and per-day usage counters — not your text.
- **Claude (API):** your text is sent to Anthropic using the API key you provide. Your key is stored in
  the macOS Keychain and never leaves your machine except as the `x-api-key` header to Anthropic.

## Dictation
If you use voice input, audio is transcribed using Apple's Speech framework. Apple may process this per
their privacy policy.

## Permissions
- **Microphone / Speech:** only used while you actively dictate.
- **Accessibility:** only used to copy your current selection and paste the rewrite back when you press
  the in-place hotkey.

## Your choices
- Pick the **Built-in AI** or **Ollama** engine to keep everything on-device.
- For the newsletter option, you can unsubscribe at any time via the link in any newsletter email, and
  "Sign out" in the app to delete the local token.

## Contact
Questions: open an issue at https://github.com/uxvic/rewrite/issues
