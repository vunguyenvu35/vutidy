import SwiftUI
import CoreKit
import Modules

/// Dưới kết quả Smart Scan: tiến trình AI agent đang chạy (kèm sub-agent) và bước tư vấn AI tùy chọn.
struct AgentsPanel: View {
    @EnvironmentObject var state: AppState
    @ViewState private var showPayload = false
    /// nil = tự động: mở khi có tiến trình đáng ngờ, còn lại thu gọn (cùng kiểu panel "Sẽ dọn những gì").
    @ViewState private var open: Bool? = nil
    var isOpen: Bool { open ?? ((state.smart?.flaggedAgents.count ?? 0) > 0) }

    var agents: [AgentProcess] { state.smart?.agents ?? [] }
    var visible: Bool { state.smart != nil && !state.smartScanning && (!agents.isEmpty || state.aiAdvisorEnabled) }

    var body: some View {
        if visible {
            VStack(alignment: .leading, spacing: 16) {
                if !agents.isEmpty { agentsCard }
                if state.aiAdvisorEnabled { advisorCard }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func ask(_ a: AgentProcess) {
        state.confirmRequest = ConfirmRequest(
            title: trf("Kết thúc %@?", a.kind.displayName),
            message: trf("PID %@ · %@\n\nGửi tín hiệu thoát (SIGTERM). Công việc chưa lưu của tiến trình này có thể mất.", "\(a.pid)", a.command),
            confirmTitle: tr("Kết thúc"), destructive: true, symbol: "v.warn",
            action: { Task { await state.terminateAgent(a) } })
    }

    // MARK: Agents

    var summary: String {
        let mem = ByteFormat.string(agents.reduce(0) { $0 + $1.footprint })
        let flagged = state.smart?.flaggedAgents.count ?? 0
        var s = trf("%@ tiến trình · %@", "\(agents.count)", mem)
        if flagged > 0 { s += " · " + trf("%@ đáng ngờ", "\(flagged)") }
        return s
    }

    var agentsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { open = !isOpen } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tr("AI agent đang chạy")).font(Theme.Font.heading).foregroundStyle(Theme.Text.primary)
                        Text(summary).font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.Text.tertiary)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .padding(.horizontal, 18).padding(.vertical, 14).contentShape(Rectangle())
            }.buttonStyle(PlainPointerStyle())
            if isOpen { ForEach(agents.prefix(12)) { a in
                Divider().overlay(Theme.Border.subtle)
                row(a)
            } }
            if isOpen && agents.count > 12 {
                Text(trf("+%@ tiến trình khác", "\(agents.count - 12)")).font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary)
                    .padding(.horizontal, 18).padding(.bottom, 12)
            }
        }
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.06)))
    }

    func badge(_ a: AgentProcess) -> String? {
        if a.orphaned { return tr("Mồ côi") }
        if a.runaway { return tr("Ngốn CPU") }
        if a.parentAgent != nil { return tr("Sub-agent") }
        return nil
    }

    func uptime(_ a: AgentProcess) -> String {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.day, .hour, .minute]; f.unitsStyle = .abbreviated; f.maximumUnitCount = 2
        f.calendar = { var c = Calendar.current; c.locale = L10n.locale; return c }()
        return trf("Chạy %@", f.string(from: max(60, a.elapsed)) ?? "")
    }

    func row(_ a: AgentProcess) -> some View {
        HStack(spacing: 12) {
            if a.parentAgent != nil { Image(systemName: "arrow.turn.down.right").font(.system(size: 10)).foregroundStyle(Theme.Text.tertiary) }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(a.kind.displayName).font(.vt(size: 13.5, weight: .semibold)).foregroundStyle(Theme.Text.primary)
                    if let b = badge(a) {
                        Text(b).font(.vt(size: 11, weight: .medium))
                            .foregroundStyle(a.canTerminate ? Theme.Review.text : Theme.Text.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                    }
                }
                Text(uptime(a)).font(.vt(size: 11)).foregroundStyle(Theme.Text.tertiary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(String(format: "%.0f%%", a.cpu)).font(Theme.Font.caption).monospacedDigit().foregroundStyle(Theme.Text.secondary)
            Text(ByteFormat.string(a.footprint)).font(.vt(size: 13, weight: .semibold)).monospacedDigit()
                .foregroundStyle(Theme.Text.primary).frame(width: 78, alignment: .trailing)
            if a.canTerminate {
                Button(tr("Kết thúc")) { ask(a) }.buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(.leading, a.parentAgent != nil ? 34 : 18).padding(.trailing, 18).padding(.vertical, 9)
        .help("PID \(a.pid) · \(a.command)")
    }

    // MARK: Tư vấn AI

    var advisorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("Tư vấn AI")).font(Theme.Font.heading).foregroundStyle(Theme.Text.primary)
                    Text(tr("Gửi số liệu tổng hợp tới Claude API. Không có đường dẫn hay tên file. AI chỉ khuyên, không tự xóa gì.")).font(Theme.Font.caption)
                        .foregroundStyle(Theme.Text.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                if state.adviceLoading { VSpinner(size: 16) }
                else if state.aiHasKey {
                    Button(state.advice == nil ? tr("Hỏi AI") : tr("Hỏi lại")) { Task { await state.askAdvisor() } }.buttonStyle(SecondaryButtonStyle())
                } else {
                    Button(tr("Thêm API key…")) { state.settingsOpen = true }.buttonStyle(SecondaryButtonStyle())
                }
            }
            if let a = state.advice { Text(a).font(.vt(size: 13)).lineSpacing(3).foregroundStyle(Theme.Text.primary).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true) }
            if let e = state.adviceError { Text(e).font(Theme.Font.caption).foregroundStyle(Theme.Review.text).fixedSize(horizontal: false, vertical: true) }
            Button { showPayload.toggle() } label: {
                Text(showPayload ? tr("Ẩn dữ liệu sẽ gửi") : tr("Xem dữ liệu sẽ gửi")).font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary)
            }.buttonStyle(PlainPointerStyle())
            if showPayload, let p = state.aiPayload {
                Text(ScanAdvisor.json(p)).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.Text.secondary).textSelection(.enabled)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.25)))
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.06)))
    }
}

/// Ô nhập API key trong Settings. Key chỉ vào Keychain, không hiển thị lại.
struct AdvisorKeyField: View {
    @EnvironmentObject var state: AppState
    @ViewState private var draft = ""
    var body: some View {
        HStack(spacing: 8) {
            if state.aiHasKey {
                Label(tr("Đã lưu trong Keychain"), systemImage: "checkmark.seal").font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary)
                Button(tr("Xóa key")) { AdvisorKeychain.delete(); state.aiHasKey = false }.buttonStyle(SecondaryButtonStyle())
            } else {
                SecureField("sk-ant-…", text: $draft).textFieldStyle(.roundedBorder).frame(width: 200)
                Button(tr("Lưu")) {
                    if AdvisorKeychain.save(draft) { state.aiHasKey = AdvisorKeychain.hasKey; draft = "" }
                }.buttonStyle(SecondaryButtonStyle()).disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}
