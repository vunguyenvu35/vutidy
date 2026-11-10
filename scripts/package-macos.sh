#!/usr/bin/env bash
# Đóng gói dist/Vutidy.app thành dist/vutidy-<version>-macos.{dmg,zip} cùng file .sha256.
# Usage: scripts/package-macos.sh [--build]
#   --build   chạy scripts/make-app.sh trước (ARCHS=universal để build universal)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(tr -d '[:space:]' < VERSION)"
DIST="${DIST_DIR:-dist}"
APP="$DIST/Vutidy.app"
OUT="$DIST"
BASE="vutidy-${VERSION}-macos"

if [ "${1:-}" = "--build" ]; then
  scripts/make-app.sh
fi
if [ ! -d "$APP" ]; then
  echo "error: $APP not found (run scripts/make-app.sh or pass --build)" >&2
  exit 1
fi

mkdir -p "$OUT"
rm -f "$OUT/$BASE.zip" "$OUT/$BASE.dmg" "$OUT/$BASE.sha256"

# ZIP: ditto giữ symlink, resource fork và chữ ký.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT/$BASE.zip"

# DMG: app + lối tắt /Applications để kéo-thả cài đặt.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
cp THIRD_PARTY_NOTICES.md "$STAGE/"
[ -f LICENSE ] && cp LICENSE "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Vutidy $VERSION" -srcfolder "$STAGE" \
  -fs HFS+ -format UDZO -ov "$OUT/$BASE.dmg" >/dev/null

(cd "$OUT" && shasum -a 256 "$BASE.dmg" "$BASE.zip" | tee "$BASE.sha256")
echo "done: $OUT/$BASE.dmg, $OUT/$BASE.zip"
