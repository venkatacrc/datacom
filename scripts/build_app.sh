#!/usr/bin/env bash
# Builds build/Datacom.app from the Swift package in app/.
#   ./scripts/build_app.sh            # then: open build/Datacom.app
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Datacom.app"
RES="$ROOT/app/Sources/Datacom/Resources"

# Rebuild the libraries from the source repos: web/library.json (public) and the app's full copy.
python3 "$ROOT/tools/build_library.py" --app "$RES/library.json"

# The app renders lessons with the same scripts and styles as the web app.
rm -rf "$RES/web"
mkdir -p "$RES/web"
cp "$ROOT/web/render.js" "$ROOT/web/content.css" "$RES/web/"
cp -R "$ROOT/web/katex" "$RES/web/katex"

# The Command Line Tools toolchain can't start the new SwiftPM build system,
# so fall back to the native one when it fails.
SWIFT_FLAGS=(-c release --package-path "$ROOT/app")
if ! swift build "${SWIFT_FLAGS[@]}" 2>/dev/null; then
    SWIFT_FLAGS+=(--build-system native)
    swift build "${SWIFT_FLAGS[@]}"
fi
BIN="$(swift build "${SWIFT_FLAGS[@]}" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Datacom" "$APP/Contents/MacOS/Datacom"
cp "$RES/library.json" "$APP/Contents/Resources/"
cp -R "$RES/web" "$APP/Contents/Resources/web"

ICONSET="$ROOT/build/AppIcon.iconset"
rm -rf "$ICONSET"
swift "$ROOT/scripts/make_icon.swift" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Datacom</string>
    <key>CFBundleDisplayName</key><string>Datacom</string>
    <key>CFBundleIdentifier</key><string>com.venkatacrc.datacom</string>
    <key>CFBundleExecutable</key><string>Datacom</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.education</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>DatacomRepo</key><string>$ROOT</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP"
