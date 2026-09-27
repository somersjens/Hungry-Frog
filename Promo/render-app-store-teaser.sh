#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
DERIVED_DATA="/tmp/hungry-frog-promo-derived"
BUNDLE_ID="Hakketjak.Hungry-Frog"
EXPORT_DIR="$PROJECT_ROOT/promo/exports"
STAGING_DIR="$PROJECT_ROOT/promo/.exports-staging"

cd "$PROJECT_ROOT"

DEVICE_ID="$(xcrun simctl list devices available -j | /usr/bin/python3 -c 'import json,sys; data=json.load(sys.stdin); print(next(d["udid"] for runtime in data["devices"].values() for d in runtime if d.get("isAvailable") and "iPhone" in d.get("name", "")))')"

xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE_ID" -b

xcodebuild \
  -project "Hungry Frog.xcodeproj" \
  -scheme "Hungry Frog" \
  -configuration Release \
  -sdk iphonesimulator \
  -destination "platform=iOS Simulator,id=$DEVICE_ID" \
  -derivedDataPath "$DERIVED_DATA" \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS=TRAILER_EXPORT \
  CODE_SIGNING_ALLOWED=NO \
  build

APP_PATH="$DERIVED_DATA/Build/Products/Release-iphonesimulator/Hungry Frog.app"
xcrun simctl install "$DEVICE_ID" "$APP_PATH"
xcrun simctl terminate "$DEVICE_ID" "$BUNDLE_ID" 2>/dev/null || true
CONTAINER="$(xcrun simctl get_app_container "$DEVICE_ID" "$BUNDLE_ID" data)"

# This path belongs only to the compile-gated exporter. Clearing it prevents a
# previous completion marker from being mistaken for the new render.
rm -rf "$CONTAINER/Documents/AppStoreTeaser"
xcrun simctl launch "$DEVICE_ID" "$BUNDLE_ID" --export-app-store-teaser

COMPLETE="$CONTAINER/Documents/AppStoreTeaser/export-complete.json"
FAILED="$CONTAINER/Documents/AppStoreTeaser/export-failed.txt"

for _ in {1..1800}; do
  if [[ -f "$FAILED" ]]; then
    /bin/cat "$FAILED"
    exit 1
  fi
  if [[ -f "$COMPLETE" ]]; then
    break
  fi
  sleep 2
done

[[ -f "$COMPLETE" ]] || { echo "Trailer export timed out."; exit 1; }

rm -rf "$STAGING_DIR"
ditto "$CONTAINER/Documents/AppStoreTeaser" "$STAGING_DIR"
mkdir -p "$EXPORT_DIR"
rm -rf "$EXPORT_DIR/previews" "$EXPORT_DIR/contact-sheets"
rm -f "$EXPORT_DIR"/frog-app-store-teaser-*.mp4(N)
rm -f "$EXPORT_DIR/export-complete.json" "$EXPORT_DIR/export-failed.txt"
ditto "$STAGING_DIR" "$EXPORT_DIR"
rm -rf "$STAGING_DIR"

PYTHON="/Users/jenssomers/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3"
if [[ -x "$PYTHON" ]]; then
  "$PYTHON" "$PROJECT_ROOT/promo/make-contact-sheets.py" "$EXPORT_DIR"
fi

echo "Exports copied to $EXPORT_DIR"
