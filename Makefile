# Lối tắt cho các script trong scripts/. `make help` để xem danh sách.
.PHONY: help dev build package test

help:
	@echo "make dev      build debug dist/Vutidy.app và mở (nhanh, để phát triển)"
	@echo "make build    build release riêng từng kiến trúc: dist/arm64/Vutidy.app (M1–M5) và dist/x86_64/Vutidy.app (Intel)"
	@echo "make package  build release rồi đóng gói dist/vutidy-<version>-macos.{dmg,zip}"
	@echo "make test     swift test"

dev:
	scripts/dev.sh

build:
	@for a in arm64 x86_64; do \
		CONFIG=release ARCHS=$$a DIST_DIR=dist/$$a scripts/make-app.sh || exit 1; \
	done

package:
	scripts/package-macos.sh --build

test:
	swift test
