#!/bin/zsh
# Builds, signs, notarizes and staples the FVoice DMG.
# Usage: tool/package.sh <version> [notary args...]
#   Local:  tool/package.sh 0.1.0 --keychain-profile fvoice-notary
#   CI:     tool/package.sh 0.1.0 --key "$KEY_PATH" --key-id "$KEY_ID" --issuer "$ISSUER"
set -euo pipefail

VERSION="${1:?usage: tool/package.sh <version> [notary args...]}"
shift
NOTARY_ARGS=("$@")
IDENTITY="Developer ID Application: Jacob Moura (U843T2P7A2)"
APP="build/Build/Products/Release/FVoice.app"
DMG="dist/FVoice-${VERSION}-macos.dmg"

echo "==> Generating project and building Release ${VERSION}"
xcodegen generate
xcodebuild -scheme FVoice -configuration Release -derivedDataPath build \
  MARKETING_VERSION="${VERSION}" CURRENT_PROJECT_VERSION="${VERSION}" build | tail -2

echo "==> Re-signing Sparkle internals (nested bundles need explicit Developer ID)"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
for target in \
  "$SPARKLE/Versions/B/XPCServices/Installer.xpc" \
  "$SPARKLE/Versions/B/XPCServices/Downloader.xpc" \
  "$SPARKLE/Versions/B/Updater.app" \
  "$SPARKLE/Versions/B/Autoupdate" \
  "$SPARKLE"; do
  if [[ -e "$target" ]]; then
    codesign --force --timestamp --options runtime --sign "$IDENTITY" "$target"
  fi
done

echo "==> Re-signing the app bundle"
codesign --force --timestamp --options runtime \
  --entitlements FVoice/App/FVoice.entitlements --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"

echo "==> Creating DMG"
mkdir -p dist
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "FVoice" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

echo "==> Notarizing"
xcrun notarytool submit "$DMG" "${NOTARY_ARGS[@]}" --wait

echo "==> Stapling"
xcrun stapler staple "$DMG"
spctl -a -t open --context context:primary-signature -vv "$DMG"

echo "==> Done: $DMG"
