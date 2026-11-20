# Lối tắt cho các script trong scripts/. `make help` để xem danh sách.
.PHONY: help dev build package test

help:
	@echo "make dev      build debug dist/Vutidy.app và mở (nhanh, để phát triển)"
	@echo "make build    build release riêng từng kiến trúc: dist/arm64/Vutidy.app (M1–M5) và dist/x86_64/Vutidy.app (Intel);"
	@echo "              bản hợp với máy đang dùng còn được chép ra dist/Vutidy.app"
	@echo "make package  build release rồi đóng gói dist/vutidy-<version>-macos.{dmg,zip}"
	@echo "make test     swift test"

dev:
	scripts/dev.sh

build:
	@for a in arm64 x86_64; do \
		CONFIG=release ARCHS=$$a DIST_DIR=dist/$$a scripts/make-app.sh || exit 1; \
	done
	@# Chép bản đúng kiến trúc của máy này ra dist/Vutidy.app để luôn mở được bản mới nhất ở một đường dẫn quen thuộc
	@# (thay bản cũ, không để lại bản cũ khi build lại). dist/<arch>/ vẫn giữ nguyên để đóng gói.
	@arch=$$(uname -m); \
	rm -rf dist/Vutidy.app && ditto dist/$$arch/Vutidy.app dist/Vutidy.app && \
	echo "dist/Vutidy.app <- dist/$$arch/Vutidy.app (v$$(cat VERSION))"

package:
	scripts/package-macos.sh --build

test:
	swift test
