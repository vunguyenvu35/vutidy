import SwiftUI
import CoreKit
import Modules

struct SmartScanView: View {
    @EnvironmentObject var state: AppState
    @ViewState private var confirm = false

    var body: some View {
        let disk = state.snapshot?.disk
        let cleanable = state.smart?.cleanableBytes ?? 0
        VStack(alignment: .leading, spacing: 16) {
            hero(disk: disk, cleanable: cleanable).frame(minHeight: 280, maxHeight: .infinity)
            HStack(alignment: .top, spacing: 14) {
                moduleCard(tr("Dọn dẹp"), symbol: "v.systemJunk", tint: Page.systemJunk.palette.glow, page: .systemJunk) {
                    ForEach([(tr("Rác hệ thống"), "system-junk"), ("Dev Junk", "dev-junk"), (tr("Thùng rác"), "trash")], id: \.1) { name, id in
                        row(name, id == "trash" && state.trashBlocked && (state.results[id] ?? []).isEmpty
                                ? tr("Cần Full Disk Access")
                                : ByteFormat.string((state.results[id] ?? []).filter { $0.safety == .safe }.reduce(0) { $0 + $1.allocatedSize }))
                    }
                    row(tr("Cần xem lại"), ByteFormat.string(state.smart?.reviewBytes ?? 0))
                }
                moduleCard(tr("Bảo vệ"), symbol: "v.protection", tint: Page.protection.palette.glow, page: .protection) {
                    row(tr("Launch items"), "\(state.smart?.persistence.count ?? 0)")
                    row(tr("Chưa ký / thiếu file"), "\(state.smart?.suspiciousCount ?? 0)")
                    row(tr("Cảnh báo real-time"), "\(state.alerts.count)")
                    row("Real-time", state.realtimeOn ? tr("Đang chạy") : tr("Đã tắt"))
                }
                moduleCard(tr("Tăng tốc"), symbol: "v.optimization", tint: Page.optimization.palette.glow, page: .optimization) {
                    row(tr("Launch agent (user)"), "\(state.smart?.launchItems.filter { $0.scope == .userAgent }.count ?? 0)")
                    row("RAM", state.snapshot.map { ByteFormat.string($0.memory.available) + tr(" khả dụng") } ?? "—")
                    row("CPU", "\(Int((state.snapshot?.cpuLoad ?? 0) * 100))%")
                    row("Swap", state.snapshot.map { ByteFormat.string($0.memory.swapUsed) } ?? "—")
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .smooth(state.smartScanning).smooth(state.smart == nil).smooth(state.cleaning.isEmpty)
        .confirmDialog(isPresented: $confirm, title: trf("Dọn %@?", ByteFormat.string(cleanable)),
                       message: trf("Chỉ các mục an toàn. Bạn có thể khôi phục trong %@ ngày. Thùng rác sẽ được dọn vĩnh viễn và mục dùng lệnh CLI (docker, go, brew) không hoàn tác được.", "\(state.retentionDays)"),
                       confirmTitle: tr("Chuyển vào Quarantine"), symbol: "v.smartScan") {
            Task { await state.cleanSmart(mode: .quarantine) }
        }
    }

    // MARK: Hero

    func hero(disk: DiskInfo?, cleanable: Int64) -> some View {
        HStack(spacing: 30) {
            ZStack {
                Ring(segments: ringSegments(disk), lineWidth: 14)
                VStack(spacing: 1) {
                    Text(ByteFormat.string(disk?.availableImportant ?? 0)).font(.vt(size: 26, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.55).multilineTextAlignment(.center)
                    Text(cleanable > 0 ? trf("→ %@ sau khi dọn", ByteFormat.string((disk?.availableImportant ?? 0) + cleanable)) : tr("trống"))
                        .font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary).lineLimit(1).minimumScaleFactor(0.7)
                }.multilineTextAlignment(.center).frame(width: 172 - 14 * 2 - 24)
            }.frame(width: 172, height: 172)

            VStack(alignment: .leading, spacing: 10) {
                Text(state.smart.map { trf("Quét lúc %@", $0.date.formatted(date: .abbreviated, time: .shortened)) } ?? tr("Chưa quét"))
                    .font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary)
                Text(state.smart == nil ? tr("Quét Mac của bạn") : (cleanable == 0 ? tr("Mac của bạn đang gọn gàng") : trf("Mac của bạn có thể lấy lại %@", ByteFormat.string(cleanable))))
                    .font(.vt(size: 28, weight: .semibold)).foregroundStyle(.white).lineLimit(2)
                if !state.cleaning.isEmpty {
                    HStack(spacing: 10) { VSpinner(size: 18); Text(tr("Đang dọn…")).font(.vt(size: 14, weight: .semibold)).foregroundStyle(.white) }
                } else if state.smartScanning {
                    HStack(spacing: 10) { VSpinner(size: 18); Text(state.status["smart"] ?? tr("Đang quét…")).font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary) }
                } else if state.smart == nil {
                    Text(tr("Smart Scan gộp Rác hệ thống, Dev Junk, Thùng rác, persistence và gợi ý tối ưu trong một lần quét."))
                        .font(Theme.Font.body).foregroundStyle(Theme.Text.secondary).fixedSize(horizontal: false, vertical: true)
                } else if cleanable > 0 {
                    Label(trf("Hoàn tác được trong %@ ngày", "\(state.retentionDays)"), systemImage: "arrow.uturn.backward")
                        .font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary)
                }
                HStack(spacing: 10) {
                    if !state.smartScanning && state.cleaning.isEmpty {
                        if state.smart != nil && cleanable > 0 {
                            Button(trf("Dọn %@", ByteFormat.string(cleanable))) { confirm = true }.buttonStyle(PrimaryButtonStyle())
                            Button(tr("Xem trước (dry-run)")) { Task { await state.cleanSmart(mode: .dryRun) } }.buttonStyle(SecondaryButtonStyle())
                        }
                        if state.smart == nil { Button(tr("Bắt đầu quét")) { Task { await state.runSmartScan() } }.buttonStyle(PrimaryButtonStyle()) }
                        else { Button { Task { await state.runSmartScan() } } label: { Label(tr("Quét lại"), systemImage: "arrow.clockwise") }.buttonStyle(SecondaryButtonStyle()) }
                    }
                }.padding(.top, 2)
            }
            Spacer(minLength: 0)
            HeroArt(page: .smartScan, size: 132).frame(width: 150, height: 150).padding(.trailing, 8)
        }
        .padding(.horizontal, 26).padding(.vertical, 20)
        .glassSurface(radius: Theme.Radius.hero, strong: true)
    }

    func ringSegments(_ d: DiskInfo?) -> [Ring.Segment] {
        guard let d, d.total > 0 else { return [] }
        let used = Double(d.total - d.availableImportant - d.purgeable)
        return [.init(value: used, color: Color.white.opacity(0.92)), .init(value: Double(d.purgeable), color: Color.white.opacity(0.5)),
                .init(value: Double(d.availableImportant), color: Color.white.opacity(0.16))]
    }

    func row(_ l: String, _ v: String) -> some View {
        HStack { Text(l).foregroundStyle(Theme.Text.secondary); Spacer(); Text(v).foregroundStyle(Theme.Text.primary).monospacedDigit() }.font(Theme.Font.body)
    }

    func moduleCard<C: View>(_ title: String, symbol: String, tint: Color, page: Page, @ViewBuilder content: () -> C) -> some View {
        Button { state.section = page } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    SolidIcon(symbol: symbol, tint: tint, size: 28)
                    Text(title).font(Theme.Font.heading).foregroundStyle(Theme.Text.primary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.Text.tertiary)
                }
                content()
            }
            .padding(16).frame(maxWidth: .infinity, minHeight: 184, maxHeight: 184, alignment: .topLeading)
            .glassSurface(radius: Theme.Radius.card, strong: false)
            .contentShape(Rectangle())
        }.buttonStyle(PlainPointerStyle())
    }
}
