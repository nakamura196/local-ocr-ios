#!/usr/bin/env zsh
# Build a Release archive and an App Store .ipa; optionally upload it to App Store Connect (TestFlight).
#
# Prerequisites:
#   - xcodegen, Xcode with the team Q6S8JS6GWV signed in
#   - For --upload: the app record for com.nakamura196.localocr exists in App Store Connect,
#     and the App Store Connect API key is set up as for KotenOCR
#     (APP_STORE_API_KEY / APP_STORE_API_ISSUER in ~/git/hi/miyako/koten-ocr-ios/.env,
#      key file at ~/.private_keys/AuthKey_<KEY_ID>.p8)
#
# Usage:
#   zsh scripts/archive.zsh            # archive + export only
#   zsh scripts/archive.zsh --upload   # archive + export + upload
#
# Before each upload, raise CURRENT_PROJECT_VERSION in project.yml (build numbers must increase).
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
OUT="$PROJECT_DIR/build"
ARCHIVE="$OUT/LocalOCR.xcarchive"
EXPORT="$OUT/export"
ENV_FILE="$HOME/git/hi/miyako/koten-ocr-ios/.env"

cd "$PROJECT_DIR"
xcodegen generate -q
rm -rf "$OUT"
mkdir -p "$OUT"

echo "[1/3] Archive (Release)"
xcodebuild -project LocalOCR.xcodeproj -scheme LocalOCR -configuration Release -destination "generic/platform=iOS" -archivePath "$ARCHIVE" -allowProvisioningUpdates -quiet archive

echo "[2/3] Export .ipa"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist scripts/ExportOptions.plist -exportPath "$EXPORT" -allowProvisioningUpdates -quiet
IPA="$(ls "$EXPORT"/*.ipa | head -1)"
echo "  $IPA ($(du -h "$IPA" | cut -f1))"

if [[ "${1:-}" == "--upload" ]]; then
  echo "[3/3] Upload to App Store Connect"
  KEY="$(grep '^APP_STORE_API_KEY=' "$ENV_FILE" | cut -d= -f2)"
  ISSUER="$(grep '^APP_STORE_API_ISSUER=' "$ENV_FILE" | cut -d= -f2)"
  xcrun altool --upload-app --type ios --file "$IPA" --apiKey "$KEY" --apiIssuer "$ISSUER"
  unset KEY ISSUER
  echo "Uploaded. Processing takes 5-30 minutes before the build appears in TestFlight."
else
  echo "[3/3] Skipped upload (pass --upload)"
fi

/usr/libexec/PlistBuddy -c "Print :ApplicationProperties:CFBundleShortVersionString" -c "Print :ApplicationProperties:CFBundleVersion" "$ARCHIVE/Info.plist"
