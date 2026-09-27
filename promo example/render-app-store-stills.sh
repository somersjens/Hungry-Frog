#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
DERIVED_DATA="/tmp/flying-penguin-promo-derived"
BUNDLE_ID="Hakketjak.Flying-Penguin"
EXPORT_DIR="$PROJECT_ROOT/promo/exports"
STAGING_DIR="$PROJECT_ROOT/promo/.stills-staging"

cd "$PROJECT_ROOT"

DEVICE_ID="$(xcrun simctl list devices available -j | /usr/bin/python3 -c 'import json,sys; data=json.load(sys.stdin); print(next(d["udid"] for runtime in data["devices"].values() for d in runtime if d.get("isAvailable") and "iPhone" in d.get("name", "")))')"

xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
open -gj -a Simulator --args -CurrentDeviceUDID "$DEVICE_ID"
xcrun simctl bootstatus "$DEVICE_ID" -b

xcodebuild \
  -project "Flying Penguin.xcodeproj" \
  -scheme "Flying Penguin" \
  -configuration Release \
  -sdk iphonesimulator \
  -destination "platform=iOS Simulator,id=$DEVICE_ID" \
  -derivedDataPath "$DERIVED_DATA" \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS=TRAILER_EXPORT \
  CODE_SIGNING_ALLOWED=NO \
  build

APP_PATH="$DERIVED_DATA/Build/Products/Release-iphonesimulator/Flying Penguin.app"
xcrun simctl install "$DEVICE_ID" "$APP_PATH"
xcrun simctl terminate "$DEVICE_ID" "$BUNDLE_ID" 2>/dev/null || true
CONTAINER="$(xcrun simctl get_app_container "$DEVICE_ID" "$BUNDLE_ID" data)"
rm -rf "$CONTAINER/Documents/AppStoreStills"
xcrun simctl launch "$DEVICE_ID" "$BUNDLE_ID" --export-app-store-stills

COMPLETE="$CONTAINER/Documents/AppStoreStills/export-complete.json"
FAILED="$CONTAINER/Documents/AppStoreStills/export-failed.txt"

for _ in {1..180}; do
  if [[ -f "$FAILED" ]]; then
    /bin/cat "$FAILED"
    exit 1
  fi
  if [[ -f "$COMPLETE" ]]; then
    break
  fi
  sleep 1
done

[[ -f "$COMPLETE" ]] || { echo "Still export timed out."; exit 1; }

rm -rf "$STAGING_DIR"
ditto "$CONTAINER/Documents/AppStoreStills" "$STAGING_DIR"
mkdir -p "$EXPORT_DIR"
/bin/cp "$STAGING_DIR"/*.png "$EXPORT_DIR/"
rm -rf "$STAGING_DIR"

echo "Still exports copied to $EXPORT_DIR"
