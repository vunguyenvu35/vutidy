# Kế hoạch xây dựng ứng dụng dọn dẹp & tối ưu macOS

> Trạng thái: **Draft để review** (rev 2: bổ sung Menu Bar Popover, Recommendation Engine, Real-time Monitor)
> Tham chiếu tính năng: CleanMyMac X / CleanMyMac 5 (chỉ clone tính năng, không dùng tên/logo/UI)
> Tên dự án: _TBD_

---

## 1. Mục tiêu

- Clone đầy đủ nhóm tính năng của một app cleaner thương mại: dọn rác, quản lý dung lượng, gỡ app, tối ưu hiệu năng, bảo vệ, giám sát hệ thống.
- **Khác biệt:** module dọn rác cho developer (Docker, JetBrains, Go, Node, PHP, Xcode, Homebrew, LLM models).
- **An toàn là ưu tiên số 1:** không bao giờ xóa vĩnh viễn ngay, mọi thao tác đều có thể hoàn tác.
- Native, nhẹ, nhanh. Không telemetry mặc định.

### Non-goals (giai đoạn đầu)

- Không phải antivirus đầy đủ. Real-time protection v1 chỉ dựa trên **FSEvents** (phát hiện sau khi file đã ghi), **không** dùng Endpoint Security / System Extension.
- iPhone battery qua private API `MobileDevice` chỉ là tính năng thử nghiệm, tắt mặc định.
- Không phát hành trên Mac App Store (sandbox chặn phần lớn tính năng).
- Không hỗ trợ macOS < 13.

---

## 2. Bản đồ tính năng

| Nhóm | Tính năng | Mô tả | Cần root |
|---|---|---|---|
| Smart Scan | Smart Scan | Quét tổng hợp 1 nút, gộp kết quả từ các module | Một phần |
| Cleanup | System Junk | User/system cache, logs, language files, broken prefs, broken login items | Một phần |
| Cleanup | Mail Attachments | File đính kèm Mail đã tải về local | Không |
| Cleanup | Photo Junk | Cache/thumbnail Photos library | Không |
| Cleanup | Trash Bins | Thùng rác user, volume ngoài, Trash của từng app | Một phần |
| Cleanup | **Dev Junk** | Docker, IDE caches, build caches, package caches | Không |
| Protection | Malware Removal | Signature (YARA) + quét persistence | Một phần |
| Protection | Privacy | Lịch sử/cookies trình duyệt, recent items, xem quyền TCC | Không |
| Speed | Optimization | Login items, Launch Agents/Daemons, app ngốn CPU/RAM | Một phần |
| Speed | Maintenance | Flush DNS, free purgeable RAM, reindex Spotlight, thin Time Machine snapshots | Có |
| Applications | Uninstaller | Gỡ app + leftovers, reset app | Một phần |
| Applications | Updater | Kiểm tra bản cập nhật app (Sparkle, Homebrew, MAS) | Không |
| Applications | Extensions | Safari extensions, plugins, preference panes, Spotlight/QuickLook plugins | Một phần |
| Files | Space Lens | Trực quan hóa dung lượng (sunburst/treemap) | Không |
| Files | Large & Old Files | Lọc file theo size/tuổi/loại | Không |
| Files | Duplicates | Tìm file trùng (size → partial hash → full hash) | Không |
| Files | Shredder | Xóa file an toàn | Không |
| Cloud | Cloud Cleanup | Evict bản local của iCloud/Google Drive/OneDrive | Không |
| Monitor | Menu Bar Popover | Disk (kèm purgeable), RAM, battery, CPU load + nhiệt độ, Wi-Fi, quick actions | Một phần |
| Monitor | Recommendations | Thẻ gợi ý có action, sinh từ kết quả scan và trạng thái hệ thống | Không |
| Monitor | Connected Devices | Pin thiết bị Bluetooth (chuột, bàn phím, tai nghe); iPhone (thử nghiệm) | Không |
| Monitor | Speed Test | Đo tốc độ mạng qua `networkQuality` | Không |
| Protection | Real-time Monitor | Quét file mới ở các vị trí nhạy cảm qua FSEvents | Không |

---

## 3. Kiến trúc

### 3.1 Tech stack

| Thành phần | Lựa chọn | Lý do |
|---|---|---|
| Ngôn ngữ | Swift 5.9+ | Truy cập trực tiếp API hệ thống, concurrency tốt |
| UI | SwiftUI (+ AppKit khi cần) | Native, nhẹ |
| Min OS | macOS 13 Ventura | `SMAppService`, SwiftUI ổn định |
| Privileged ops | `SMAppService.daemon` + XPC | Cách Apple khuyến nghị thay cho `SMJobBless` |
| Update app | Sparkle 2 | Chuẩn cho app phân phối ngoài MAS |
| Malware rules | YARA (libyara qua C interop) | Chuẩn ngành, có rule cộng đồng |
| Lưu trữ | SQLite (GRDB) | Lịch sử thao tác, quarantine index, cache scan |
| Build | SPM, xcodebuild, GitHub Actions | Tách package dễ test |

### 3.2 Sơ đồ thành phần

```
┌──────────────────────────────────────────────────────────┐
│                     App (SwiftUI)                        │
│  SmartScan │ Cleanup │ Protection │ Speed │ Apps │ Files │
└───────────────┬──────────────────────────────┬───────────┘
                │                              │
        ┌───────▼────────┐            ┌────────▼────────┐
        │  Core Package  │            │  Menu Bar Agent │
        │ ScanEngine     │            │ (LaunchAgent)   │
        │ RuleEngine     │            └─────────────────┘
        │ SafetyLayer    │
        │ ActionExecutor │
        └───────┬────────┘
                │ XPC (verify code signature)
        ┌───────▼────────────┐
        │ Privileged Helper  │  (root, SMAppService.daemon)
        │ - delete system    │
        │ - flush DNS        │
        │ - purge            │
        │ - tmutil thin      │
        └────────────────────┘
```

### 3.3 Cấu trúc package

```
Sources/
├── CoreKit/            # model chung, logging, utils
├── ScanEngine/         # file walker, size calculator
├── RuleEngine/         # load + evaluate rules
├── SafetyLayer/        # blocklist, quarantine, undo, dry-run
├── Modules/
│   ├── SystemJunk/
│   ├── DevJunk/
│   ├── Uninstaller/
│   ├── SpaceLens/
│   ├── LargeOldFiles/
│   ├── Duplicates/
│   ├── Maintenance/
│   ├── Optimization/
│   ├── Privacy/
│   ├── Malware/
│   ├── Updater/
│   ├── CloudCleanup/
│   ├── Recommendations/
│   ├── RealtimeMonitor/
│   └── DeviceMonitor/
├── HelperProtocol/     # XPC protocol dùng chung app ↔ helper
├── PrivilegedHelper/   # target helper
└── MenuBarAgent/       # target agent
Rules/                  # *.yaml rule definitions (ship kèm app, update được)
```

### 3.4 Interface module

```swift
protocol CleanerModule {
    var id: String { get }
    var requiresPrivilege: Bool { get }
    func scan(progress: ScanProgress) async throws -> [ScanItem]
    func clean(_ items: [ScanItem], mode: CleanMode) async throws -> CleanReport
}

enum CleanMode { case dryRun, moveToTrash, quarantine, permanent }

struct ScanItem: Identifiable, Hashable {
    let id: UUID
    let url: URL
    let allocatedSize: Int64
    let category: String
    let ruleID: String
    let safety: SafetyLevel   // .safe, .review, .dangerous
    var selected: Bool
}
```

---

## 4. Scan Engine

- **File walker:** dùng `getattrlistbulk` (nhanh hơn nhiều so với `FileManager.enumerator`) với `fts` làm fallback.
- **Concurrency:** `TaskGroup` theo thư mục cấp 1, giới hạn số task song song để không làm treo I/O.
- **Size:** tính `allocatedSize` (`ATTR_FILE_ALLOCSIZE`) chứ không dùng logical size. Lưu ý APFS clones và purgeable space, nên tổng hiển thị phải ghi rõ là ước tính.
- **Hard links:** dedupe theo `(dev, ino)`.
- **Cache kết quả:** lưu snapshot vào SQLite để lần quét sau chỉ quét diff dựa trên mtime của thư mục.
- **Cancel/progress:** hỗ trợ cancel giữa chừng và stream progress lên UI.

---

## 5. Rule Engine

Rules tách khỏi code, ship dạng YAML để cập nhật mà không cần release app.

```yaml
- id: user-caches
  module: system-junk
  title: "User cache files"
  paths:
    - "~/Library/Caches/*"
  exclude:
    - "~/Library/Caches/com.apple.*"
    - "~/Library/Caches/CloudKit"
  conditions:
    min_age_days: 0
    app_not_running: true      # bỏ qua cache của app đang chạy
  safety: safe
  action: trash

- id: jetbrains-caches
  module: dev-junk
  title: "JetBrains IDE caches"
  paths:
    - "~/Library/Caches/JetBrains/*"
  conditions:
    app_not_running_bundle: "com.jetbrains.*"
  safety: safe
  action: trash

- id: jetbrains-orphan-config
  module: dev-junk
  title: "Config/cache của IDE đã gỡ hoặc version cũ"
  detector: jetbrains_orphans   # rule cần logic riêng → gọi detector
  safety: review
  action: trash
```

Phân loại safety:

| Level | Hành vi mặc định |
|---|---|
| `safe` | Tự chọn sẵn |
| `review` | Hiển thị nhưng không tự chọn |
| `dangerous` | Chỉ hiển thị, phải xác nhận riêng |

---

## 6. Safety Layer (bắt buộc ngay Phase 0)

- **Blocklist cứng:** `/System`, `/usr` (trừ `/usr/local` khi có rule rõ ràng), `/bin`, `/sbin`, `~/Documents`, `~/Desktop`, `~/Pictures/Photos Library.photoslibrary/originals`, keychains, `.ssh`, `.gnupg`, cùng mọi thứ có SIP protection.
- **Mặc định:** chuyển vào Trash (`FileManager.trashItem`). Với file hệ thống, chuyển vào quarantine `~/Library/Application Support/<app>/Quarantine/` kèm index trong SQLite.
- **Retention quarantine:** 7 ngày (cấu hình được), sau đó tự xóa.
- **Undo:** khôi phục từ quarantine về đúng path gốc, giữ nguyên permission và xattrs.
- **Dry-run mode:** mọi module đều phải hỗ trợ.
- **Audit log:** ghi mọi thao tác xóa/di chuyển (path, size, rule, thời gian).
- **App đang chạy:** không động vào cache, container hay prefs của app đang chạy.

---

## 7. Chi tiết module

### 7.1 System Junk

- User cache: `~/Library/Caches`
- System cache: `/Library/Caches` (qua helper)
- Logs: `~/Library/Logs`, `/Library/Logs`, `/private/var/log` (chỉ file đã rotate)
- Language files: `*.lproj` không dùng trong app bundle. **Cảnh báo:** làm hỏng code signature, nên mặc định tắt hoặc chỉ cho phép với app không được sign.
- Broken preferences: plist parse lỗi
- Broken login items: trỏ tới app không còn tồn tại
- Xcode junk: chuyển sang Dev Junk

### 7.2 Dev Junk (khác biệt chính)

| Nguồn | Phát hiện | Hành động |
|---|---|---|
| Docker | `docker system df -v` | `docker image prune`, `docker builder prune`, `docker volume prune` (volume để `review`), gợi ý compact `Docker.raw` |
| JetBrains | `~/Library/Caches/JetBrains`, `~/Library/Logs/JetBrains`, `~/Library/Application Support/JetBrains/<IDE><version>` | Xóa cache; phát hiện IDE đã gỡ hoặc version cũ |
| Go | `go env GOCACHE GOMODCACHE` | `go clean -cache`, `go clean -modcache` (`review`) |
| Node | Cache của npm/yarn/pnpm, `node_modules` trong project | Xóa cache; liệt kê `node_modules` của project có mtime > N ngày |
| PHP | `~/.composer/cache`, `vendor/` project cũ | Như Node |
| Python | `~/Library/Caches/pip`, `__pycache__`, venv cũ | Như Node |
| Xcode | DerivedData, Archives, iOS DeviceSupport, simulators | `xcrun simctl delete unavailable` |
| Homebrew | `brew --cache` | `brew cleanup -s` |
| LLM | `~/.ollama/models`, `~/.cache/huggingface` | Chỉ liệt kê, `review`, không tự chọn |

Quét project: cho người dùng chọn các thư mục gốc (`~/Projects`, `~/Code`…), không quét toàn bộ home.

### 7.3 Uninstaller

- Liệt kê app trong `/Applications`, `~/Applications`, kèm size, ngày dùng cuối (`kMDItemLastUsedDate`), nguồn (MAS/Homebrew/khác).
- Tìm leftovers theo **bundle ID** và **tên app** trong:
  - `~/Library/{Application Support, Caches, Preferences, Containers, Group Containers, Saved Application State, HTTPStorages, WebKit, Logs, LaunchAgents, Cookies}`
  - `/Library/{Application Support, LaunchAgents, LaunchDaemons, PrivilegedHelperTools, Preferences}`
  - Receipts: `pkgutil --pkgs`, `pkgutil --files <id>`
- Hành động: Uninstall, Reset (chỉ xóa data, giữ app), xóa leftovers của app đã gỡ trước đó.
- Unload launch agents/daemons trước khi xóa (`launchctl bootout`).
- App cài qua Homebrew: gợi ý dùng `brew uninstall --cask` thay vì xóa tay.

### 7.4 Optimization

- Login items: `SMAppService` status cho app hiện đại, BTM database (`sfltool dumpbtm`, chỉ đọc) để liệt kê.
- Launch Agents/Daemons: liệt kê plist, trạng thái loaded, enable/disable (không xóa).
- Heavy consumers: `proc_pid_rusage`, `proc_pidinfo` để lấy top CPU/RAM/energy theo khoảng thời gian.

### 7.5 Maintenance

| Tác vụ | Lệnh/API | Giữ lại? |
|---|---|---|
| Flush DNS | `dscacheutil -flushcache; killall -HUP mDNSResponder` | ✅ |
| Free RAM | `purge` | ✅ (giải thích rõ hiệu quả hạn chế) |
| Reindex Spotlight | `mdutil -E /` | ✅ |
| Thin TM local snapshots | `tmutil listlocalsnapshots`, `tmutil thinlocalsnapshots` | ✅ |
| Rebuild Launch Services | `lsregister -kill -r -domain local -domain system -domain user` | ✅ |
| Periodic scripts | `periodic daily weekly monthly` | ❌ Deprecated, bỏ |
| Repair disk permissions | — | ❌ Vô nghĩa từ SIP, bỏ |
| Verify disk | `diskutil verifyVolume /` | ✅ (chỉ verify) |

### 7.6 Space Lens

- Dựng cây thư mục từ Scan Engine, tính size bottom-up.
- Visualization: sunburst (Canvas/SwiftUI) hoặc treemap (squarified).
- Drill-down, breadcrumb, "Reveal in Finder", chuyển sang Trash.
- Quét theo volume, hỗ trợ ổ ngoài.

### 7.7 Large & Old Files

- Filter: size > N, chưa mở > N ngày (`kMDItemLastUsedDate`, fallback `atime`), theo loại (archive, video, disk image, installer).
- Gợi ý nhóm: file `.dmg`/`.pkg` trong Downloads, video lớn, archive cũ.

### 7.8 Duplicates

1. Nhóm theo size (bỏ file < 1KB).
2. Partial hash (4KB đầu + 4KB cuối).
3. Full hash (xxHash3 hoặc BLAKE3) cho các ứng viên còn lại.
4. Nhận diện APFS clone (không tốn thêm dung lượng) và đánh dấu riêng.
5. Gợi ý giữ bản cũ nhất hoặc bản trong thư mục ưu tiên.

### 7.9 Privacy

- Trình duyệt (Safari, Chrome, Firefox, Arc, Edge, Brave): history, cookies, cache, form data. Đọc/xóa SQLite, **yêu cầu đóng trình duyệt trước**.
- Recent items, Quick Look cache, recent files trong Finder.
- Quyền TCC: đọc `TCC.db` (cần FDA) để hiển thị app nào có quyền gì; reset qua `tccutil reset <service> <bundleID>`.

### 7.10 Malware / Protection

Phạm vi thực tế: **persistence scanner + signature scan**, không phải AV real-time.

- Persistence: LaunchAgents/Daemons, login items, cron, kernel/system extensions, browser extensions, configuration profiles, `/etc/hosts`, DNS settings, authorization plugins.
- Với mỗi item: kiểm tra code signature (`SecStaticCodeCheckValidity`), notarization, Team ID, đánh dấu item unsigned hoặc ad-hoc.
- Signature: YARA rules (nguồn cộng đồng, cập nhật định kỳ).
- Hành động: disable, rồi quarantine, rồi xóa (có undo).

#### Real-time Monitor (FSEvents)

- Chạy trong Menu Bar Agent, dùng `FSEventStreamCreate` với flag `kFSEventStreamCreateFlagFileEvents`.
- Vị trí theo dõi: `~/Downloads`, `~/Desktop`, `/Applications`, `~/Applications`, `~/Library/LaunchAgents`, `/Library/LaunchAgents`, `/Library/LaunchDaemons`, `/Library/PrivilegedHelperTools`.
- Pipeline: event, debounce (file đang ghi), lọc theo loại (Mach-O, app bundle, `.dmg`, `.pkg`, script, plist persistence), rồi YARA scan + kiểm tra code signature.
- File mới trong `LaunchAgents`/`LaunchDaemons` luôn được cảnh báo, kể cả khi sạch, vì đây là kênh persistence phổ biến nhất.
- Kiểm tra thêm xattr `com.apple.quarantine` để biết nguồn tải về.
- UI: trạng thái ON/OFF, "Last file scanned", thời điểm cập nhật signature DB, nút Check Now.
- Giới hạn tài nguyên: queue có giới hạn, bỏ qua file > 500MB (cấu hình được), ưu tiên thấp (`QoS .utility`).
- **Giới hạn cần ghi rõ trong UI:** chỉ phát hiện sau khi file đã ghi, không chặn được việc thực thi. Chặn trước khi chạy cần Endpoint Security (để dành cho v2, cần xin entitlement Apple).

### 7.11 Updater

- Sparkle: đọc `SUFeedURL` trong `Info.plist`, parse appcast.
- MAS apps: iTunes Lookup API theo bundle ID.
- Homebrew casks: `brew outdated --cask --greedy`.
- Còn lại: so sánh version với nguồn đã biết (best effort).
- Chỉ thông báo và mở trang tải/MAS, không tự cài (giai đoạn đầu).

### 7.12 Cloud Cleanup

- iCloud Drive: `FileManager.evictUbiquitousItem(at:)`.
- File Provider (Google Drive, OneDrive, Dropbox): `NSFileProviderManager` evict nếu provider hỗ trợ.
- Chỉ evict bản local, không xóa trên cloud.

### 7.13 Menu Bar Popover

Popover gồm 3 vùng: **Recommendations** (carousel ngang), **Overview** (lưới widget), **Footer** (mở app, settings).

| Widget | Dữ liệu | API / cách lấy | Quick action |
|---|---|---|---|
| Protection | Trạng thái real-time, last file scanned, DB update | Real-time Monitor (7.10) | Check Now (cập nhật signature) |
| Disk | Available, purgeable | `volumeAvailableCapacityForImportantUsage`, `volumeAvailableCapacity`, `volumeTotalCapacity` | Free Up (mở Cleanup / thin TM snapshots) |
| Memory | Available, pressure, swap | `host_statistics64`, `vm.swapusage`, `DispatchSource.makeMemoryPressureSource` | Free Up (`purge` qua helper) |
| Battery | %, trạng thái sạc, cycle count, health | IOKit `IOPSCopyPowerSourcesInfo`, `AppleSmartBattery` | — |
| CPU | Load, nhiệt độ | `host_processor_info`; nhiệt độ: SMC (Intel) / `IOHIDEventSystemClient` (Apple Silicon, private) | Mở danh sách heavy consumers |
| Wi-Fi | Up/down realtime, SSID | `getifaddrs` delta mỗi 1–2s; SSID qua CoreWLAN (cần quyền Location) | Test Speed |
| Connected Devices | Tên + % pin | Xem 7.16 | — |

Yêu cầu chung:

- Agent tách process, idle CPU < 1%, RAM < 50MB. Polling chỉ tăng tần suất khi popover đang mở.
- Nhiệt độ CPU trên Apple Silicon dùng private API: bọc sau protocol `SensorProvider`, nếu lỗi thì ẩn widget, không crash.
- Cảnh báo (notification): disk sắp đầy, app ngốn CPU kéo dài, memory pressure cao, nhiệt độ cao kéo dài.

### 7.14 Smart Scan

- Orchestrator chạy song song: System Junk, Dev Junk (safe), Malware (persistence), Optimization (gợi ý).
- Kết quả gộp vào 3 thẻ: Cleanup, Protection, Speed. Một nút "Run" chỉ áp dụng các item `safe`.

### 7.15 Recommendation Engine

Sinh các thẻ gợi ý có action (hiển thị ở popover và màn hình chính).

```swift
struct Recommendation: Identifiable {
    let id: String              // ổn định để nhớ trạng thái dismiss
    let priority: Int
    let icon: String
    let title: String           // "Free 13,95 GB of purgeable space."
    let actionTitle: String     // "Free Up Space"
    let action: RecommendationAction
}

protocol RecommendationProvider {
    func evaluate(context: SystemContext) async -> [Recommendation]
}
```

Provider ban đầu:

| Provider | Điều kiện | Action |
|---|---|---|
| Purgeable space | Purgeable > 5GB | Thin TM snapshots / mở Cleanup |
| Disk low | Free < 10% | Mở Space Lens |
| Malware scan cũ | Chưa deep scan > 7 ngày | Run Deep Scan |
| Dev junk lớn | Dev Junk safe > 5GB (từ lần quét gần nhất) | Mở Dev Junk |
| App outdated | Updater có ≥ 1 bản cập nhật | Mở Updater |
| App không dùng | App chưa mở > 90 ngày | Mở Uninstaller |
| Login items nhiều | > N login items/agents | Mở Optimization |
| Battery health | Health < 80% | Mở thông tin pin |

- Đánh giá định kỳ (mặc định 30 phút) và sau mỗi lần scan; chỉ dùng dữ liệu cache, không tự quét nặng.
- Dismiss: ẩn theo `id` trong N ngày (lưu SQLite). Nếu điều kiện xấu hơn đáng kể thì hiện lại.
- Thứ tự: theo `priority`, tối đa 5 thẻ.
- Provider định nghĩa ngưỡng trong YAML giống Rule Engine để chỉnh không cần release.

### 7.16 Connected Devices & Speed Test

**Connected Devices**

- Bluetooth HID (chuột, bàn phím, trackpad): IOKit, service `AppleDeviceManagementHIDEventService`, key `BatteryPercent`.
- Tai nghe/AirPods: `system_profiler SPBluetoothDataType -json` (chậm, chỉ gọi khi mở popover, cache 60s).
- iPhone/iPad (**thử nghiệm, tắt mặc định**): framework private `MobileDevice`, chỉ thiết bị đã pair (USB hoặc Wi-Fi sync). Có thể vỡ khi lên bản macOS mới.
- Cảnh báo khi pin thiết bị < 20%.

**Speed Test**

- Dùng `networkQuality -c` (macOS 12+), parse JSON: download, upload, responsiveness (RPM).
- Chạy trong agent, hiển thị progress, lưu lịch sử 20 lần gần nhất.
- Không tự chạy định kỳ (tốn băng thông).

---

## 8. Quyền & phân phối

| Hạng mục | Cách làm |
|---|---|
| Full Disk Access | Onboarding hướng dẫn, kiểm tra bằng cách thử đọc `~/Library/Safari` hoặc TCC.db |
| Privileged helper | `SMAppService.daemon`, người dùng approve trong System Settings → Login Items |
| XPC security | Helper verify code signature + Team ID của caller (`setCodeSigningRequirement`, macOS 13+) |
| Signing | Developer ID Application, Hardened Runtime |
| Notarization | `notarytool` trong CI |
| Update | Sparkle 2 + EdDSA signature |
| Distribution | DMG + Homebrew cask |

---

## 9. Roadmap

| Phase | Nội dung | Ước tính (1 dev) | Deliverable |
|---|---|---|---|
| **0. Nền móng** | Package structure, Scan Engine, Rule Engine, Safety Layer (quarantine/undo/dry-run), helper + XPC, onboarding FDA, CI notarize | 2–3 tuần | App rỗng chạy được, quét/di chuyển file an toàn |
| **1. MVP dung lượng** | Space Lens, Large & Old Files, System Junk, Dev Junk, Trash Bins | 3–4 tuần | **Bản dùng thật đầu tiên** |
| **2. App management** | Uninstaller + leftovers, Extensions, Login items/Launch agents | 2–3 tuần | |
| **3. Performance + Popover** | Maintenance, heavy consumers, Menu Bar Popover (widget + quick actions), Connected Devices (Bluetooth), Speed Test, Recommendation Engine (provider cơ bản) | 3–4 tuần | Popover hoàn chỉnh trừ Protection |
| **4. Mở rộng** | Updater, Cloud Cleanup, Duplicates, Mail/Photo junk | 3 tuần | |
| **5. Protection** | Persistence scanner, YARA, Privacy cleaner, Real-time Monitor (FSEvents), widget Protection, provider malware | 4–5 tuần | |
| **6. Hoàn thiện** | Smart Scan, scheduler, i18n vi/en, docs, release 1.0 | 2 tuần | v1.0 |

**Tổng:** khoảng 19–24 tuần cho 1 dev.

---

## 10. Testing

- **Unit test:** Rule Engine, Safety Layer (blocklist bắt buộc 100% coverage).
- **Fixture filesystem:** tạo cây thư mục giả trong temp dir để test scan/clean.
- **VM test:** chạy trên VM macOS sạch (UTM/Tart) cho mọi thao tác cần root.
- **Dry-run diff:** so sánh kết quả dry-run với thao tác thật.
- **Performance benchmark:** thời gian quét home directory ~500k file, mục tiêu < 30s trên M1.

---

## 11. Rủi ro

| Rủi ro | Mức độ | Giảm thiểu |
|---|---|---|
| Xóa nhầm dữ liệu người dùng | Cao | Safety Layer từ Phase 0, quarantine, blocklist, `review` mặc định cho cái không chắc |
| Malware module thành "theater" | Trung bình | Giới hạn phạm vi, không quảng cáo là antivirus |
| Thay đổi API giữa các bản macOS | Trung bình | Rules tách khỏi code, CI test trên nhiều bản macOS |
| Xóa language files làm hỏng signature | Trung bình | Tắt mặc định |
| Trademark | Thấp | Không dùng tên/logo/UI của sản phẩm tham chiếu |
| Size báo cáo sai do APFS clone/purgeable | Thấp | Dùng allocated size, ghi rõ là ước tính |
| Private API (nhiệt độ CPU, MobileDevice) vỡ khi update macOS | Trung bình | Bọc sau protocol, fail thì ẩn widget; iPhone tắt mặc định |
| Người dùng hiểu nhầm FSEvents monitor là AV real-time | Trung bình | Ghi rõ giới hạn trong UI và docs |
| Menu bar agent tốn pin | Thấp | Polling thích ứng, benchmark idle CPU trong CI |

---

## 12. Câu hỏi cần chốt

- [ ] Mục tiêu: tool cá nhân hay sản phẩm phát hành (open source / thương mại)?
- [ ] Tên dự án?
- [ ] Có cần hỗ trợ Intel Mac không, hay chỉ Apple Silicon?
- [ ] Phase 1 có bao gồm Dev Junk ngay hay để sau?
- [ ] Có cần chế độ CLI (headless) song song với GUI không?
- [ ] Malware module: tự viết rules hay dùng nguồn YARA cộng đồng?
- [ ] Real-time Monitor: đồng ý FSEvents cho v1, Endpoint Security để v2? _(plan đang giả định có)_
- [ ] iPhone battery: giữ dạng thử nghiệm hay bỏ hẳn? _(plan đang giả định giữ, tắt mặc định)_
