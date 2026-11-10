# Third-party notices

Vutidy contains **no third-party source code and no third-party packages**. `Package.swift` declares no dependencies.

## System frameworks

Vutidy uses only frameworks that ship with macOS and Swift, under Apple's licences: Swift standard library and Foundation, SwiftUI, AppKit, Combine, CryptoKit (SHA-256), Security (code-signature checks), CoreServices (Spotlight metadata, FSEvents), IOKit (battery, power sources), Darwin/Mach (memory and CPU statistics) and Testing (swift-testing, tests only).

## Command line tools it may run

When present on your Mac, Vutidy runs these tools you already have installed; none are bundled: `docker`, `go`, `brew`, `launchctl`, `networkQuality`, `system_profiler`, `tmutil`, `mdutil`, `diskutil`, `dscacheutil`, `killall`, `purge`, `lsregister`, `osascript`, `ps`, `networksetup`.

## Fonts

The app uses the macOS system fonts (SF Pro, SF Pro Rounded, SF Mono). The logo files in `docs/assets/brand/` reference **JetBrains Mono** (SIL Open Font License 1.1) and **Inter** (SIL Open Font License 1.1) only in the font stacks of their SVG text; no font file is included, and the PNG renders contain the glyphs as images.

## Brand and trademarks

Vutidy reproduces the *features* of cleaner apps but uses no name, logo or artwork of any other product. All product names mentioned (macOS, Docker, JetBrains, Xcode, Homebrew, …) belong to their owners.

## Licence

Vutidy itself is released under the MIT License: see the [LICENSE](LICENSE) file.
