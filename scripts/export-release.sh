#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

VERSION="${VERSION:-1.0.0}"
BUILD="${BUILD:-1}"

DIST_DIR="$ROOT_DIR/dist"
STAGING_DIR="$DIST_DIR/staging"
DMG_STAGE="$STAGING_DIR/dmg"
ZIP_STAGE="$STAGING_DIR/zip"

APP_NAME="CXW focus.app"
APP_DIR="$DMG_STAGE/$APP_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
HELPERS_DIR="$CONTENTS_DIR/Helpers"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

DMG_PATH="$DIST_DIR/CXW-focus-${VERSION}.dmg"
ZIP_PATH="$DIST_DIR/CXW-focus-${VERSION}.zip"

rm -rf "$STAGING_DIR" "$DMG_PATH" "$ZIP_PATH"
mkdir -p "$MACOS_DIR" "$HELPERS_DIR" "$RESOURCES_DIR" "$ZIP_STAGE"

echo "==> Building Universal release binary (arm64 + x86_64)..."
APP_BIN=""
CLI_BIN=""
XCODE_DEV="/Applications/Xcode.app/Contents/Developer"
if [ -d "$XCODE_DEV" ] && DEVELOPER_DIR="$XCODE_DEV" swift build -c release --arch arm64 --arch x86_64; then
    if [ -f ".build/apple/Products/Release/FocusDock" ] && [ -f ".build/apple/Products/Release/focusdock-cli" ]; then
        APP_BIN=".build/apple/Products/Release/FocusDock"
        CLI_BIN=".build/apple/Products/Release/focusdock-cli"
    fi
fi

if [ -z "$APP_BIN" ]; then
    echo "==> Falling back to native release build..."
    swift build -c release
    APP_BIN=".build/release/FocusDock"
    CLI_BIN=".build/release/focusdock-cli"
fi

cp "$APP_BIN" "$MACOS_DIR/CXWFocus"
cp "$CLI_BIN" "$HELPERS_DIR/cxwfocus"
chmod +x "$MACOS_DIR/CXWFocus" "$HELPERS_DIR/cxwfocus"

echo "==> Packaged binary architectures:"
lipo -info "$MACOS_DIR/CXWFocus"

echo "==> Generating AppIcon.icns..."
ICONSET_DIR="$STAGING_DIR/CXWFocus.iconset"
swift "$ROOT_DIR/scripts/generate-icon.swift" "$ICONSET_DIR"
iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"
rm -rf "$ICONSET_DIR"

echo "==> Writing Info.plist..."
cat > "$CONTENTS_DIR/Info.plist" << PLIST
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
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD}</string>
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

echo "==> Ad-hoc signing $APP_NAME..."
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

cat > "$DMG_STAGE/首次安装说明.txt" << 'TXT'
CXW focus 安装说明（macOS 14+）
================================

1. 将「CXW focus.app」拖入「Applications（应用程序）」文件夹。
2. 由于本软件为个人本地编译版本（未使用付费 Apple 开发者证书公证），
   首次从网络或微信接收后打开，若系统提示「无法验证开发者」或「已损坏」，
   请打开「终端（Terminal）」执行一次以下命令后即可正常打开：

   xattr -cr "/Applications/CXW focus.app"

3. 权限与快捷功能提示：
   - 打开后菜单栏会出现准星图标，点击可选择或自定义「开发 / 写作 / 学习」沉浸档位。
   - 如需启用「最小化窗口显示在 Dock 右侧」和「记住窗口布局」，请在菜单栏点击「授权」授予一次辅助功能权限。
   - 如需按档位静音不同通知，可在系统「快捷指令」中绑定专注模式后在设置里关联。
TXT

# Prepare ZIP stage and DMG Applications symlink
ditto "$APP_DIR" "$ZIP_STAGE/$APP_NAME"
cp "$DMG_STAGE/首次安装说明.txt" "$ZIP_STAGE/首次安装说明.txt"
ln -s /Applications "$DMG_STAGE/Applications"

echo "==> Creating ZIP archive: $ZIP_PATH"
ditto -c -k --sequesterRsrc "$ZIP_STAGE" "$ZIP_PATH"

echo "==> Creating DMG disk image: $DMG_PATH"
hdiutil create -volname "CXW focus" -srcfolder "$DMG_STAGE" -ov -format UDZO "$DMG_PATH"

rm -rf "$STAGING_DIR"

echo "==> Export complete:"
ls -lh "$DMG_PATH" "$ZIP_PATH"
