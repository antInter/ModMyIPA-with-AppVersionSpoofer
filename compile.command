#!/bin/bash
# macOS/Xcode only. No Apple credentials, signing secrets, or ldid required.
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$PWD"
BUILD="$ROOT/build"
DIST="$ROOT/dist"
command -v xcodebuild >/dev/null || { echo 'Use macOS/Xcode or the GitHub Actions workflow.'; exit 1; }
mkdir -p "$DIST"
xcodebuild -resolvePackageDependencies -project ModMyIPA.xcodeproj -scheme ModMyIPA \
  -derivedDataPath "$BUILD" -onlyUsePackageVersionsFromResolvedFile
xcodebuild -project ModMyIPA.xcodeproj -scheme ModMyIPA \
  -configuration Release -destination 'generic/platform=iOS' -sdk iphoneos \
  -derivedDataPath "$BUILD" -disableAutomaticPackageResolution \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' \
  DEVELOPMENT_TEAM='' ONLY_ACTIVE_ARCH=NO ARCHS=arm64 build
APP="$BUILD/Build/Products/Release-iphoneos/ModMyIPA.app"
test -f "$APP/Info.plist"
test -f "$APP/ModMyIPA"
STAGING=$(mktemp -d "$BUILD/package.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
mkdir "$STAGING/Payload"
ditto "$APP" "$STAGING/Payload/ModMyIPA.app"
rm -f "$DIST/VersionEditor-unsigned.ipa" "$DIST/VersionEditor-adhoc.ipa"
(cd "$STAGING" && /usr/bin/zip -qry "$DIST/VersionEditor-unsigned.ipa" Payload)
# Extra ad-hoc artifact for TrollStore testing. Not Apple-signed or permasigned.
while IFS= read -r -d '' item; do
  /usr/bin/codesign --force --sign - --timestamp=none "$item"
done < <(find "$STAGING/Payload/ModMyIPA.app" -depth \( -name '*.framework' -o -name '*.dylib' \) -print0)
/usr/bin/codesign --force --sign - --timestamp=none --entitlements "$ROOT/ModMyIPA.xml" "$STAGING/Payload/ModMyIPA.app"
/usr/bin/codesign --verify --deep --strict "$STAGING/Payload/ModMyIPA.app"
(cd "$STAGING" && /usr/bin/zip -qry "$DIST/VersionEditor-adhoc.ipa" Payload)
python3 scripts/verify_ipa.py "$DIST/VersionEditor-unsigned.ipa" "$DIST/VersionEditor-adhoc.ipa"
(cd "$DIST" && shasum -a 256 VersionEditor-unsigned.ipa VersionEditor-adhoc.ipa > SHA256SUMS.txt)
echo 'IPAs are in dist/. Re-sign with your sideloading tool or install using TrollStore.'
