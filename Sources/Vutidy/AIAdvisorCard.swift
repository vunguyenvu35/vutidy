import SwiftUI
import CoreKit
import Modules

/// Bảng màu riêng của AI Advisor: tính năng chủ lực nên có bản sắc thị giác riêng, không dùng chung kiểu kính của các panel khác.
enum AIStyle {
    static let violet = Color(hex: 0x8B7CFF)
    static let pink = Color(hex: 0xD36BFF)
    static let cyan = Color(hex: 0x5CC8FF)
    static let reclaim = Color(hex: 0x4FD1C5)
    static let text = Color(hex: 0xE4E0FF)
    static let body = Color(hex: 0xB9B3DA)
    static var gradient: LinearGradient { LinearGradient(colors: [violet, pink], startPoint: .topLeading, endPoint: .bottomTrailing) }
}

/// Nút hành động chính của AI: gradient tím-hồng có quầng sáng.
struct AIButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.vt(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1).fixedSize()
            .padding(.horizontal, 20).frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(AIStyle.gradient))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .shadow(color: AIStyle.pink.opacity(configuration.isPressed ? 0.2 : 0.45), radius: 14, y: 6)
            .opacity(enabled ? (configuration.isPressed ? 0.88 : 1) : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: 11))
            .pointerCursor()
    }
}

/// Thẻ AI Advisor ngay dưới hero của Smart Scan: lời mời bật, lấy kế hoạch, đang phân tích, và kế hoạch bấm-được kèm tổng dung lượng lấy lại.
struct AIAdvisorCard: View {
    @EnvironmentObject var state: AppState
    @ViewState private var showPayload = false

    enum Mode { case off, setup, ready, loading, plan, text, error }

    var mode: Mode {
        if !state.aiAdvisorEnabled { return .off }
        if state.adviceLoading { return .loading }
        if !state.aiCanAsk { return .setup }
        if state.adviceError != nil { return .error }
        if state.advicePlan != nil, !state.planRows.isEmpty { return .plan }
        if state.advice != nil { return .text }
        return .ready
    }

    var sourceName: String {
        state.aiProvider == .auto ? (AdvisorProvider.installedCLIs.first?.displayName ?? "AI") : state.aiProvider.displayName
    }

    var subtitle: String {
        switch mode {
        case .off: return tr("Để AI lên kế hoạch dọn dẹp")
        case .setup: return tr("Cần một nguồn AI để bắt đầu")
        case .loading: return trf("%@ đang phân tích kết quả quét…", sourceName)
        case .plan, .text: return state.adviceSource.map { trf("Trả lời bởi %@", $0) } ?? ""
        case .ready, .error: return tr("Phân tích kết quả quét và đề xuất việc nên làm")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            content
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x2B2160), Color(hex: 0x181238)], startPoint: .top, endPoint: .bottom))
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(RadialGradient(colors: [AIStyle.violet.opacity(0.40), .clear], center: .topLeading, startRadius: 0, endRadius: 460))
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(RadialGradient(colors: [AIStyle.pink.opacity(0.20), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 380))
            }
        )
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(LinearGradient(colors: [AIStyle.violet.opacity(0.95), AIStyle.pink.opacity(0.35), AIStyle.cyan.opacity(0.55)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.3))
        .shadow(color: AIStyle.violet.opacity(0.30), radius: 30, y: 14)
        .animation(state.reduceMotion ? nil : .easeOut(duration: 0.25), value: mode)
    }

    // MARK: Đầu thẻ

    var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "sparkles").font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(AIStyle.gradient))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(LinearGradient(colors: [.white.opacity(0.5), .clear], startPoint: .top, endPoint: .center)))
                .shadow(color: AIStyle.pink.opacity(0.5), radius: 12, y: 5)
            VStack(alignment: .leading, spacing: 3) {
                Text("AI Advisor").font(.vt(size: 19, weight: .bold)).tracking(-0.3).foregroundStyle(.white)
                Text(subtitle).font(.vt(size: 13)).foregroundStyle(AIStyle.body).lineLimit(2)
            }
            Spacer(minLength: 12)
            trailing
        }
    }

    @ViewBuilder var trailing: some View {
        switch mode {
        case .off: Button(tr("Bật AI Advisor")) { enable() }.buttonStyle(AIButtonStyle())
        case .setup: Button(tr("Chọn nguồn AI…")) { openSettings() }.buttonStyle(AIButtonStyle())
        case .ready: Button(tr("Lấy kế hoạch AI")) { Task { await state.askAdvisor() } }.buttonStyle(AIButtonStyle())
        case .loading: VSpinner(size: 22, color: AIStyle.text)
        case .plan, .text, .error:
            Button(mode == .error ? tr("Thử lại") : tr("Hỏi lại")) { Task { await state.askAdvisor() } }.buttonStyle(SecondaryButtonStyle())
        }
    }

    // MARK: Nội dung

    @ViewBuilder var content: some View {
        switch mode {
        case .off: offContent
        case .setup:
            Text(tr("Chưa có công cụ AI. Đăng nhập Claude Code hoặc Codex, hoặc thêm API key.")).font(.vt(size: 13.5)).foregroundStyle(AIStyle.text)
            privacy
        case .ready: privacy
        case .loading: EmptyView()
        case .plan: planContent
        case .text:
            if let a = state.advice { summaryText(a) }
            privacy
        case .error:
            if let e = state.adviceError { Text(e).font(.vt(size: 13)).foregroundStyle(Theme.Review.text).fixedSize(horizontal: false, vertical: true) }
            privacy
        }
    }

    var offContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(tr("AI chỉ xem số liệu tổng hợp, không bao giờ thấy file của bạn. Nó chọn việc đáng làm nhất, bạn bấm một lần để thực hiện."))
                .font(.vt(size: 14)).lineSpacing(3).foregroundStyle(AIStyle.text).fixedSize(horizontal: false, vertical: true)
            let found = AdvisorProvider.installedCLIs.map(\.displayName)
            HStack(spacing: 8) {
                Image(systemName: found.isEmpty ? "info.circle" : "checkmark.seal.fill").font(.system(size: 13))
                    .foregroundStyle(found.isEmpty ? AIStyle.body : AIStyle.reclaim)
                Text(found.isEmpty ? tr("Chưa phát hiện công cụ AI nào. Bạn có thể thêm API key.")
                                   : trf("Đã phát hiện %@, dùng tài khoản bạn đã đăng nhập sẵn.", found.joined(separator: ", ")))
                    .font(.vt(size: 12.5)).foregroundStyle(AIStyle.body).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    func summaryText(_ s: String) -> some View {
        Text(s).font(.vt(size: 14.5, weight: .medium)).lineSpacing(4).foregroundStyle(.white).textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Kế hoạch

    var reclaimBytes: Int64 {
        Int64(state.planRows.filter { $0.action.kind == .clean && !state.planDone.contains($0.id) }.reduce(0) { $0 + $1.action.megabytes }) * 1_000_000
    }

    @ViewBuilder var planContent: some View {
        if let s = state.advice, !s.isEmpty { summaryText(s) }
        VStack(spacing: 0) {
            ForEach(Array(state.planRows.enumerated()), id: \.element.id) { i, step in
                if i > 0 { Divider().overlay(Color.white.opacity(0.07)) }
                stepRow(i + 1, step)
            }
        }
        .padding(.horizontal, 16)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.24)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.07)))

        if !state.pendingSafeSteps.isEmpty {
            HStack(alignment: .center, spacing: 16) {
                if reclaimBytes > 0 {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(ByteFormat.string(reclaimBytes)).font(.vt(size: 26, weight: .bold, design: .rounded)).tracking(-0.5)
                            .monospacedDigit().foregroundStyle(AIStyle.reclaim)
                        Text(tr("có thể giải phóng · vào Quarantine, hoàn tác được")).font(.vt(size: 12)).foregroundStyle(AIStyle.body)
                    }
                } else {
                    Text(tr("Mục dọn vào Quarantine, hoàn tác được.")).font(.vt(size: 12)).foregroundStyle(AIStyle.body)
                }
                Spacer(minLength: 12)
                Button(trf("Áp dụng tất cả (%@)", "\(state.pendingSafeSteps.count)")) { state.confirmApplyAll() }.buttonStyle(AIButtonStyle())
            }
        }
        privacy
    }

    func stepIcon(_ a: AdvisorAction) -> String {
        switch a.kind { case .clean: return "sparkles"; case .terminateAgents: return "bolt.slash.fill"; case .review: return "magnifyingglass" }
    }

    func stepTitle(_ a: AdvisorAction) -> String {
        switch a.kind {
        case .clean: return trf("Dọn %@", a.category)
        case .terminateAgents: return trf("Kết thúc %@ AI agent đáng ngờ", "\(a.items)")
        case .review: return trf("Xem lại %@", a.category)
        }
    }

    func stepChip(_ a: AdvisorAction) -> String {
        let size = ByteFormat.string(Int64(a.megabytes) * 1_000_000)
        return a.kind == .clean ? "+" + size : size
    }

    func stepButton(_ a: AdvisorAction) -> String {
        switch a.kind { case .clean: return tr("Dọn"); case .terminateAgents: return tr("Kết thúc"); case .review: return tr("Xem") }
    }

    func stepRow(_ n: Int, _ step: AdvisorStep) -> some View {
        let a = step.action, done = state.planDone.contains(step.id)
        return HStack(spacing: 14) {
            ZStack {
                Circle().fill(done ? AnyShapeStyle(AIStyle.reclaim.opacity(0.25)) : AnyShapeStyle(AIStyle.gradient)).frame(width: 28, height: 28)
                if done { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(AIStyle.reclaim) }
                else { Text("\(n)").font(.vt(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.white) }
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(stepTitle(a)).font(.vt(size: 14, weight: .semibold)).foregroundStyle(done ? AIStyle.body : .white).lineLimit(1)
                    Text(stepChip(a)).font(.vt(size: 11.5, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(a.kind == .clean ? AIStyle.reclaim : AIStyle.body)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill((a.kind == .clean ? AIStyle.reclaim : Color.white).opacity(0.14)))
                }
                if !step.reason.isEmpty {
                    Text(step.reason).font(.vt(size: 12.5)).foregroundStyle(AIStyle.body).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 10)
            if done {
                Text(tr("Đã xong")).font(.vt(size: 12.5, weight: .medium)).foregroundStyle(AIStyle.reclaim)
            } else {
                Button(stepButton(a)) { state.confirmPerform(step) }.buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(.vertical, 12)
    }

    // MARK: Quyền riêng tư

    var privacy: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield").font(.system(size: 11))
                Text(tr("Chỉ gửi số liệu tổng hợp, không đường dẫn hay tên file. AI chỉ khuyên, mọi thay đổi do bạn bấm."))
                Button { showPayload.toggle() } label: {
                    Text(showPayload ? tr("Ẩn dữ liệu sẽ gửi") : tr("Xem dữ liệu sẽ gửi")).underline()
                }.buttonStyle(PlainPointerStyle())
            }
            .font(.vt(size: 11.5)).foregroundStyle(AIStyle.body.opacity(0.85))
            if showPayload, let p = state.aiPayload {
                Text(ScanAdvisor.json(p)).font(.system(size: 11, design: .monospaced)).foregroundStyle(AIStyle.body).textSelection(.enabled)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.3)))
            }
        }
    }

    // MARK: Hành động

    func enable() { state.aiAdvisorEnabled = true; if !state.aiCanAsk { openSettings() } }
    func openSettings() { state.settingsPage = .cleaning; state.settingsOpen = true }
}
