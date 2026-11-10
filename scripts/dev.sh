#!/bin/zsh
# Chạy Vutidy như một app thật (có icon, tên, bundle ID) để Full Disk Access hoạt động.
# `swift run` chạy file trần nên macOS tính quyền theo terminal/IDE đã mở nó, không phải theo Vutidy.app.
set -euo pipefail
cd "$(dirname "$0")/.."
# Thoát bản đang chạy từ dist/ (nếu có) để không có hai icon trên menu bar.
pkill -f "dist/Vutidy.app/Contents/MacOS/Vutidy" 2>/dev/null || true
CONFIG=${CONFIG:-debug} scripts/make-app.sh --open
cat <<'MSG'

Nếu banner Full Disk Access vẫn còn:
  1. System Settings → Privacy & Security → Full Disk Access
  2. Xóa mục Vutidy cũ bằng nút "−", rồi thêm lại dist/Vutidy.app bằng nút "+"
     (mỗi lần build lại, chữ ký ad-hoc đổi nên macOS coi là app mới)
  3. Bấm "Khởi động lại Vutidy" trên banner
MSG
