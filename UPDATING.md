# Shipping updates to installed users

The app checks a hosted `version.json` on launch. If it lists a version newer than
the running one, users see an **"UPDATE AVAILABLE → DOWNLOAD"** bar (and the same in
Settings → Updates). Download opens your `.dmg`; they drag the new app over the old.

## One-time setup
1. Create a **free public GitHub repo**, e.g. `rewrite-releases`.
2. Edit `release.sh` (top) → set `GH_USER` and `GH_REPO` to that repo.
3. Set the app's feed URL to the repo's raw `version.json`:
   - `RewriteApp/RewriteApp/Updater.swift` → `UpdateConfig.defaultFeedURL`
   - e.g. `https://raw.githubusercontent.com/<you>/rewrite-releases/main/version.json`
   - (Users can also override it in Settings → Updates is read-only; the URL is baked in.)

## Each release
```bash
cd ~/RewriteApp
./release.sh 1.1.0
```
This bumps the version, builds Release, makes `dist/Rewrite.dmg`, and writes `dist/version.json`.
Then:
1. **GitHub → Releases → Draft new release**, tag `v1.1.0`, upload `dist/Rewrite.dmg` as an asset.
2. Commit `dist/version.json` into the `rewrite-releases` repo (root), push to `main`.

Within a launch, existing users get the prompt. Done.

## Important for warning-free installs
This notifier just downloads the `.dmg`; the user still installs it. For the install to be
**warning-free**, the `.app` should be **Developer ID signed + notarized** (Apple Developer
Program, $99/yr) before you build the dmg. Until then, testers must right-click → Open the
first time. (Auto-silent updates via Sparkle are the natural next step once notarization is set up.)

## Don't forget
Bake your **gateway URL** (`GatewayConfig.swift`) in before releasing, so "Free models" works
for the people who download it.
