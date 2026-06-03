#!/bin/bash
# Build + package a Rewrite release, and generate version.json (the update feed).
#
# Usage:   ./release.sh 1.1.0
# Then:    gh release create v1.1.0 dist/Rewrite.dmg   (and commit version.json)
#
# If a "Developer ID Application" signing identity is available AND notary creds
# are set (DEVID, AC_KEYCHAIN_PROFILE), the app is signed + notarized + stapled
# for a warning-free install. Otherwise it ships ad-hoc with bypass instructions.

GH_USER="${GH_USER:-uxvic}"
GH_REPO="${GH_REPO:-rewrite}"

set -e
VERSION="$1"
if [ -z "$VERSION" ]; then echo "Usage: ./release.sh <version>  (e.g. 1.1.0)"; exit 1; fi

ROOT="$HOME/RewriteApp"
OUT="$ROOT/dist"
PLIST="$ROOT/RewriteApp/Info.plist"
ENT="$ROOT/RewriteApp/Rewrite.entitlements"

echo "▸ Version $VERSION"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$PLIST" 2>/dev/null || true

echo "▸ Building universal Release"
xcodebuild -project "$ROOT/RewriteApp.xcodeproj" -scheme Rewrite -configuration Release \
  -derivedDataPath "$ROOT/build/Release" ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO build >/dev/null
APP="$ROOT/build/Release/Build/Products/Release/Rewrite.app"
echo "  archs: $(lipo -archs "$APP/Contents/MacOS/Rewrite" 2>/dev/null)"

# Optional: Developer ID sign + notarize (warning-free).
if [ -n "$DEVID" ] && security find-identity -p codesigning -v | grep -q "Developer ID Application"; then
  echo "▸ Signing with Developer ID + hardened runtime"
  codesign --force --deep --options runtime --timestamp \
    --entitlements "$ENT" --sign "$DEVID" "$APP"
  if [ -n "$AC_KEYCHAIN_PROFILE" ]; then
    echo "▸ Notarizing (this can take a few minutes)"
    DITTO_ZIP="$OUT/notarize.zip"; mkdir -p "$OUT"
    ditto -c -k --keepParent "$APP" "$DITTO_ZIP"
    xcrun notarytool submit "$DITTO_ZIP" --keychain-profile "$AC_KEYCHAIN_PROFILE" --wait
    xcrun stapler staple "$APP"
    rm -f "$DITTO_ZIP"
    NOTARIZED=1
  fi
fi

echo "▸ Packaging dist/Rewrite.dmg"
rm -rf "$OUT/dmg"; mkdir -p "$OUT/dmg"
cp -R "$APP" "$OUT/dmg/Rewrite.app"
ln -s /Applications "$OUT/dmg/Applications"
if [ -z "$NOTARIZED" ]; then
/usr/libexec/PlistBuddy -c "Print" /dev/stdin >/dev/null 2>&1 || true
cat > "$OUT/dmg/How to open.txt" <<'TXT'
First time only — macOS may say "Rewrite cannot be verified".
This is because the app isn't notarized yet (not because it's unsafe).

To open it:
  • Right-click Rewrite.app → Open → Open
  • or: System Settings → Privacy & Security → scroll down → "Open Anyway"

You only have to do this once.
TXT
fi
hdiutil create -volname "Rewrite" -srcfolder "$OUT/dmg" -ov -format UDZO "$OUT/Rewrite.dmg" >/dev/null

DL_URL="https://github.com/$GH_USER/$GH_REPO/releases/download/v$VERSION/Rewrite.dmg"
cat > "$ROOT/version.json" <<EOF
{
  "version": "$VERSION",
  "url": "$DL_URL",
  "notes": "Rewrite $VERSION",
  "minimumSystemVersion": "14.0"
}
EOF

echo ""
echo "✅ Done — dist/Rewrite.dmg + version.json (v$VERSION)"
[ -z "$NOTARIZED" ] && echo "   (ad-hoc signed — users right-click → Open the first time. Set DEVID + AC_KEYCHAIN_PROFILE to notarize.)"
echo "   Next: gh release create v$VERSION dist/Rewrite.dmg  &&  git commit version.json"
