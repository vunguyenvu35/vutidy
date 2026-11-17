# Lối tắt cho các script trong scripts/. `make help` để xem danh sách.
.PHONY: help dev build package test

help:
	@echo "make dev      build debug dist/Vutidy.app và mở (nhanh, để phát triển)"
	@echo "make build    build release dist/Vutidy.app (ARCHS=universal để build arm64 + x86_64)"
	@echo "make package  build release rồi đóng gói dist/vutidy-<version>-macos.{dmg,zip}"
	@echo "make test     swift test"

dev:
	scripts/dev.sh

build:
	CONFIG=release scripts/make-app.sh

package:
	scripts/package-macos.sh --build

test:
	swift test
