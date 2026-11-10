#!/bin/zsh
# Đóng gói dist/Vutidy.app từ mã nguồn.
#   scripts/make-app.sh [--open]
#   CONFIG=debug|release     mặc định release (debug build nhanh hơn khi phát triển)
#   ARCHS=universal          build arm64 + x86_64 (mặc định: kiến trúc của máy build)
#   CODESIGN_IDENTITY="…"    chứng chỉ ký (mặc định ad-hoc "-"); chứng chỉ thật sẽ bật hardened runtime
#   DIST_DIR=…               thư mục đầu ra (mặc định dist)
#   BUILD_NUMBER=…           số build trong Info.plist (mặc định GITHUB_RUN_NUMBER hoặc 1)
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=${CONFIG:-release}
VERSION=$(tr -d '[:space:]' < VERSION)
BUILD_NUMBER=${BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-1}}
ARCH_FLAGS=()
[[ "${ARCHS:-}" == "universal" ]] && ARCH_FLAGS=(--arch arm64 --arch x86_64)

swift build -c "$CONFIG" --product Vutidy "${ARCH_FLAGS[@]}"
BIN=$(swift build -c "$CONFIG" "${ARCH_FLAGS[@]}" --show-bin-path)

DIST=${DIST_DIR:-dist}
APP="$DIST/Vutidy.app"
rm -rf "$APP" && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Vutidy" "$APP/Contents/MacOS/Vutidy"
cp docs/assets/brand/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Resource bundle của các target (rules.json, ảnh QR, icon app)
for b in "$BIN"/*.bundle; do cp -R "$b" "$APP/Contents/Resources/"; done

cat > "$APP/Contents/Info.plist" <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Vutidy</string>
  <key>CFBundleDisplayName</key><string>Vutidy</string>
  <key>CFBundleIdentifier</key><string>com.vutidy.app</string>
  <key>CFBundleExecutable</key><string>Vutidy</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
P

# Ký ad-hoc theo mặc định: mỗi lần build là một "app mới" với macOS nên quyền Full Disk Access có thể phải cấp lại.
# Ký bằng chứng chỉ cố định (CODESIGN_IDENTITY) để quyền được giữ qua các lần build; chứng chỉ thật cần hardened runtime
# + timestamp để có thể notarize.
IDENTITY="${CODESIGN_IDENTITY:--}"
if [[ "$IDENTITY" == "-" ]]; then
  codesign --force --deep --sign - "$APP"
else
  codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi
codesign --verify --deep --strict "$APP"

echo "Đã tạo $APP (v$VERSION, build $BUILD_NUMBER, $(lipo -archs "$APP/Contents/MacOS/Vutidy"))"
if [[ "${1:-}" == "--open" ]]; then open "$APP"; fi
