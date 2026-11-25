#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "==> Building CXW focus & cxwfocus CLI (release)..."
swift build -c release

APP_DIR="$ROOT_DIR/build/CXW focus.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
HELPERS_DIR="$CONTENTS_DIR/Helpers"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$APP_DIR" "$ROOT_DIR/build/FocusDock.app"
mkdir -p "$MACOS_DIR" "$HELPERS_DIR" "$RESOURCES_DIR"

cp ".build/release/FocusDock" "$MACOS_DIR/CXWFocus"
cp ".build/release/focusdock-cli" "$HELPERS_DIR/cxwfocus"
cp ".build/release/focusdock-cli" "$ROOT_DIR/build/cxwfocus"
cp ".build/release/focusdock-cli" "$ROOT_DIR/build/focusdock"
chmod +x "$MACOS_DIR/CXWFocus" "$HELPERS_DIR/cxwfocus" "$ROOT_DIR/build/cxwfocus" "$ROOT_DIR/build/focusdock"

echo "==> Generating AppIcon.icns..."
ICONSET_DIR="$ROOT_DIR/build/CXWFocus.iconset"
rm -rf "$ICONSET_DIR"
swift "$ROOT_DIR/scripts/generate-icon.swift" "$ICONSET_DIR"
iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"
rm -rf "$ICONSET_DIR"

echo "==> Writing Info.plist..."
cat > "$CONTENTS_DIR/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleDisplayName</key>
    <string>CXW focus</string>
    <key>CFBundleExecutable</key>
    <string>CXWFocus</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.cxw.focus</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>CXW focus</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>com.cxw.focus.url</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>cxwfocus</string>
                <string>focusdock</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

echo "==> Ad-hoc signing CXW focus.app..."
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

# Best-effort user CLI symlinks in ~/.local/bin
if mkdir -p "$HOME/.local/bin" 2>/dev/null; then
    ln -sf "$HELPERS_DIR/cxwfocus" "$HOME/.local/bin/cxwfocus"
    ln -sf "$HELPERS_DIR/cxwfocus" "$HOME/.local/bin/focusdock"
fi

echo "==> Build complete:"
echo "    App: $APP_DIR"
echo "    CLI: $ROOT_DIR/build/cxwfocus"
