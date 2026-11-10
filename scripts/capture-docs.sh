#!/bin/zsh
# Chụp ảnh màn hình cho docs/user-guide bằng cách mở app với VUTIDY_PAGE / VUTIDY_OPEN / VUTIDY_SCAN (xem AppState.init).
# usage: scripts/capture-docs.sh [tên-ảnh …]   (không tham số = chụp tất cả; ảnh ra docs/assets/screens/)
# Yêu cầu: dist/Vutidy.app (scripts/make-app.sh), cwebp (brew install webp) và quyền Screen Recording cho terminal. Ngôn ngữ ép về English.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=docs/assets/screens; mkdir -p "$OUT"
BIN=dist/Vutidy.app/Contents/MacOS/Vutidy
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cat > $TMP/wid.swift <<'S'
import CoreGraphics
// In ra id cửa sổ lớn nhất (layer 0) của Vutidy; với "--small" in cửa sổ nổi (popover).
let small = CommandLine.arguments.contains("--small")
var best = (0, 0.0)
for w in CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as! [[String: Any]] {
  guard (w["kCGWindowOwnerPID"] as? Int) == Int(CommandLine.arguments[1]) else { continue }
  let b = w["kCGWindowBounds"] as! [String: Double]; let layer = w["kCGWindowLayer"] as! Int
  if small ? (layer == 3) : (layer == 0 && b["Width"]! > 600) { let a = b["Width"]! * b["Height"]!; if a > best.1 { best = (w["kCGWindowNumber"] as! Int, a) } }
}
print(best.0)
S
swiftc -O $TMP/wid.swift -o $TMP/wid

# Feed giả cho ảnh "có bản cập nhật" (không tải gì; chỉ để màn Cài đặt hiện nút Cập nhật).
cat > $TMP/feed.json <<J
[{"tag_name":"v0.2.0","draft":false,"prerelease":true,"html_url":"https://github.com/vunguyenvu35/vutidy/releases/tag/v0.2.0",
"body":"# Vutidy 0.2.0\n- Check for updates and update from inside the app.\n- Smart Scan now lists what it will clean before you press Clean.\n- Fixes for the Large & Old Files filter menus.",
"assets":[{"name":"vutidy-0.2.0-macos.zip","browser_download_url":"https://example.invalid/vutidy-0.2.0-macos.zip"}]}]
J
# name | page | extra env | wait(s)
SHOTS=(
  "smart-scan-start|smartScan||3"
  "smart-scan-result|smartScan|VUTIDY_SCAN=smart|40"
  "system-junk-result|systemJunk|VUTIDY_SCAN=system-junk|25"
  "dev-junk-result|devJunk|VUTIDY_SCAN=dev-junk|25"
  "trash|trash|VUTIDY_SCAN=trash|10"
  "privacy-result|privacy|VUTIDY_SCAN=privacy|15"
  "protection|protection||8"
  "malware|malware||5"
  "optimization|optimization||5"
  "maintenance|maintenance||5"
  "uninstaller|uninstaller||10"
  "updates|updater||15"
  "space-lens|spaceLens|VUTIDY_SPACE=$PWD/Sources|15"
  "large-files|largeFiles||4"
  "duplicates|duplicates||4"
  "cloud-cleanup|cloud||4"
  "quarantine|quarantine||4"
  "quick-open|smartScan|VUTIDY_OPEN=palette|3"
  "confirm|systemJunk|VUTIDY_OPEN=confirm|3"
  "settings-general|smartScan|VUTIDY_SETTINGS=general|3"
  "settings-update|smartScan|VUTIDY_SETTINGS=general VUTIDY_UPDATE_FEED=file://$TMP/feed.json|8"
  "settings-cleaning|smartScan|VUTIDY_SETTINGS=cleaning|3"
  "settings-protection|smartScan|VUTIDY_SETTINGS=protection|3"
  "settings-shortcuts|smartScan|VUTIDY_SETTINGS=shortcuts|3"
  "settings-storage|smartScan|VUTIDY_SETTINGS=storage|3"
  "settings-support|smartScan|VUTIDY_SETTINGS=support|3"
  "menu-bar-popover|smartScan|VUTIDY_OPEN=popover|6"
  "fda-guide|smartScan|VUTIDY_FAKE_NOFDA=1 VUTIDY_OPEN=fdaguide|6"
  "lang-vi|systemJunk|VUTIDY_LANG=vi VUTIDY_SCAN=system-junk|20"
  "lang-ja|systemJunk|VUTIDY_LANG=ja VUTIDY_SCAN=system-junk|20"
  "lang-zh|systemJunk|VUTIDY_LANG=zh VUTIDY_SCAN=system-junk|20"
)
for s in $SHOTS; do
  IFS='|' read -r name page extra wait <<< "$s"
  if [[ $# -gt 0 && ! " $* " == *" $name "* ]]; then continue; fi
  pkill -f "Vutidy.app/Contents/MacOS/Vutidy" 2>/dev/null || true; sleep 1
  env VUTIDY_LANG=en VUTIDY_PAGE=$page ${=extra} $BIN >/dev/null 2>&1 &
  pid=$!; sleep $wait
  if [[ $name == menu-bar-popover || $name == fda-guide ]]; then id=$($TMP/wid $pid --small); else id=$($TMP/wid $pid); fi
  if [[ $id == 0 ]]; then echo "skip $name (no window)"; kill $pid 2>/dev/null; continue; fi
  screencapture -x -o -l $id "$TMP/$name.png"
  sips -Z 1800 "$TMP/$name.png" --out "$TMP/$name.s.png" >/dev/null
  [[ $name == protection ]] && sips --cropToHeightWidth 660 1800 --cropOffset 0 0 "$TMP/$name.s.png" >/dev/null  # bỏ danh sách launch item (có đường dẫn cá nhân)
  cwebp -q 82 -alpha_q 90 -m 6 -quiet "$TMP/$name.s.png" -o "$OUT/$name.webp"
  echo "ok $name"; kill $pid 2>/dev/null || true
done
pkill -f "Vutidy.app/Contents/MacOS/Vutidy" 2>/dev/null || true
