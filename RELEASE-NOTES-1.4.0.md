# Rewrite 1.4.0

A faster, friendlier chat. The composer was rebuilt, picking a rewrite style is
now a tap, model setup happens right inside the conversation, and the window
stays put until you close it.

## Highlights
- **New composer** — the send button now lives inside the input, which grows as
  you type (up to ~4 lines, then scrolls). `+` is on the left, the mic on the right.
- **Pick a style, then send** — the rewrite actions are a horizontal selector
  under the input. Tap one to choose how your text gets rewritten, then send.
- **Set up without leaving chat** — if a model needs setup, a card appears in the
  conversation to switch providers or sign in for free models, then retry.
- **Clearer free-models sign-in** — email code with a Resend button and friendlier errors.
- **Stays open** — the popover no longer closes when you click away; toggle it
  from the menu-bar icon.
- **What's new tour** — a one-time card after updating, showing what moved.

---

## Releasing this (run on a Mac — needs Xcode + the Sparkle private key)

The signed build + EdDSA-signed `appcast.xml` can only be produced on the Mac
that holds the Sparkle private key. After PR #1 is merged to `main`:

```bash
# release.sh hardcodes ROOT="$HOME/RewriteApp" — make sure the repo is there,
# or edit ROOT at the top of release.sh to your checkout path.
cd ~/RewriteApp && git checkout main && git pull

NOTES="New composer with the send button inside a growing input. Tap an action to pick a style, then send. Set up models and sign in to free models right inside the chat. The window now stays open until you close it from the menu bar." \
  ./release.sh 1.4.0

gh release create v1.4.0 dist/sparkle/Rewrite-1.4.0.zip dist/Rewrite.dmg
git add appcast.xml version.json RewriteApp/Info.plist
git commit -m "v1.4.0"
git push   # the appcast must land on main — that's the feed Sparkle reads
```

Installed users get the “update available” prompt within ~24h, or instantly via
the menu-bar → **Check for Updates…**. After updating to 1.4.0 they’ll see the
in-app **What’s new** banner once.

> Builds are ad-hoc signed (not notarized) unless `DEVID` + `AC_KEYCHAIN_PROFILE`
> are set. Existing users still auto-update fine — Sparkle verifies the download
> with the EdDSA signature regardless. Only a brand-new manual `.dmg` install
> hits Gatekeeper (right-click → Open, once).
