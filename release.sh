#!/bin/bash
# Build + package a Rewrite release for Sparkle auto-update.
#
# Usage:   ./release.sh 1.1.1
# Result:  dist/sparkle/Rewrite-<ver>.zip (Sparkle update, EdDSA-signed)
#          dist/Rewrite.dmg               (website manual download)
#          appcast.xml                    (the update feed, committed to repo)
# Then:    gh release create v<ver> dist/sparkle/Rewrite-<ver>.zip dist/Rewrite.dmg
#          git add appcast.xml && git commit && git push   (users auto-update)
#
# Optional warning-free first install: set DEVID + AC_KEYCHAIN_PROFILE to sign+notarize.

GH_USER="${GH_USER:-uxvic}"
GH_REPO="${GH_REPO:-rewrite}"

set -e
VERSION="$1"
if [ -z "$VERSION" ]; then echo "Usage: ./release.sh <version>  (e.g. 1.1.1)"; exit 1; fi

ROOT="$HOME/RewriteApp"
OUT="$ROOT/dist"
PLIST="$ROOT/RewriteApp/Info.plist"
ENT="$ROOT/RewriteApp/Rewrite.entitlements"
BIN="$ROOT/Frameworks/bin"

echo "▸ Version $VERSION"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$PLIST"

echo "▸ Building universal Release"
xcodebuild -project "$ROOT/RewriteApp.xcodeproj" -scheme Rewrite -configuration Release \
  -derivedDataPath "$ROOT/build/Release" ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO build >/dev/null
APP="$ROOT/build/Release/Build/Products/Release/Rewrite.app"
echo "  archs: $(lipo -archs "$APP/Contents/MacOS/Rewrite")"

# Keep ad-hoc signatures on the embedded Sparkle bits consistent.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

# Optional Developer ID sign + notarize (warning-free first install).
if [ -n "$DEVID" ] && security find-identity -p codesigning -v | grep -q "Developer ID Application"; then
  echo "▸ Signing with Developer ID + hardened runtime"
  codesign --force --deep --options runtime --timestamp --entitlements "$ENT" --sign "$DEVID" "$APP"
  if [ -n "$AC_KEYCHAIN_PROFILE" ]; then
    echo "▸ Notarizing"; Z="$OUT/notarize.zip"; mkdir -p "$OUT"
    ditto -c -k --keepParent "$APP" "$Z"
    xcrun notarytool submit "$Z" --keychain-profile "$AC_KEYCHAIN_PROFILE" --wait
    xcrun stapler staple "$APP"; rm -f "$Z"
  fi
fi

# Sparkle update archive (.zip) + signed appcast.
SPK="$OUT/sparkle"; rm -rf "$SPK"; mkdir -p "$SPK"
ditto -c -k --keepParent "$APP" "$SPK/Rewrite-$VERSION.zip"
# Optional "what's new" notes (generate_appcast embeds <ver>.html as the description).
if [ -n "$NOTES" ]; then
  printf '<h2>Rewrite %s</h2>\n<p>%s</p>\n' "$VERSION" "$NOTES" > "$SPK/Rewrite-$VERSION.html"
fi
echo "▸ Generating + EdDSA-signing appcast"
"$BIN/generate_appcast" "$SPK" \
  --download-url-prefix "https://github.com/$GH_USER/$GH_REPO/releases/download/v$VERSION/"
cp "$SPK/appcast.xml" "$ROOT/appcast.xml"

# Legacy feed for pre-Sparkle users (v1.0.x): nudges them to download the latest
# DMG once, after which they're on Sparkle and update automatically.
cat > "$ROOT/version.json" <<EOF
{
  "version": "$VERSION",
  "url": "https://github.com/$GH_USER/$GH_REPO/releases/latest/download/Rewrite.dmg",
  "notes": "A new version of Rewrite is available. Download it once to switch to automatic updates.",
  "minimumSystemVersion": "14.0"
}
EOF

# Website DMG (manual download).
echo "▸ Packaging dist/Rewrite.dmg"
rm -rf "$OUT/dmg"; mkdir -p "$OUT/dmg"
cp -R "$APP" "$OUT/dmg/Rewrite.app"; ln -s /Applications "$OUT/dmg/Applications"
cat > "$OUT/dmg/How to open.txt" <<'TXT'
First time only — macOS may say "Rewrite cannot be verified" (it isn't notarized yet,
not because it's unsafe). Right-click Rewrite.app → Open → Open, or System Settings →
Privacy & Security → "Open Anyway". You only do this once; future updates are automatic.
TXT
hdiutil create -volname "Rewrite" -srcfolder "$OUT/dmg" -ov -format UDZO "$OUT/Rewrite.dmg" >/dev/null

echo ""
echo "✅ v$VERSION ready:"
echo "   dist/sparkle/Rewrite-$VERSION.zip   → Sparkle update (signed)"
echo "   dist/Rewrite.dmg                    → website download"
echo "   appcast.xml                         → update feed (commit it)"
echo ""
echo "   Publish:  gh release create v$VERSION dist/sparkle/Rewrite-$VERSION.zip dist/Rewrite.dmg \\"
echo "             && git add appcast.xml && git commit -m 'v$VERSION' && git push"
