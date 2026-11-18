import SwiftUI
import CoreKit
import Modules
import SafetyLayer

/// Tiến trình AI agent trong Smart Scan và bước tư vấn AI (tùy chọn, mặc định tắt).
@MainActor
extension AppState {
    /// Kết thúc một agent đáng ngờ (mồ côi hoặc ngốn CPU kéo dài) rồi quét lại danh sách. Ghi vào nhật ký thao tác.
    func terminateAgent(_ agent: AgentProcess) async {
        let label = "\(agent.kind.displayName) · pid \(agent.pid)"
        switch await AgentProcesses.terminate(agent) {
        case .success:
            executor.audit.append(AuditRecord(date: Date(), action: "terminate-agent", path: label, bytes: agent.footprint,
                                              ruleID: "agent.\(agent.kind.rawValue)", mode: agent.orphaned ? "orphaned" : "runaway", result: "done"))
            notify(trf("Đã kết thúc %@.", label))
        case .failure(let e):
            let why: String
            switch e {
            case .gone: why = tr("Tiến trình đã tự thoát.")
            case .changed: why = tr("Tiến trình đã thay đổi, hãy quét lại.")
            case .notAllowed: why = tr("Chỉ kết thúc được tiến trình mồ côi hoặc ngốn CPU kéo dài.")
            case .failed: why = tr("Hệ thống từ chối.")
            }
            notify(trf("Không thể kết thúc %@: %@", label, why), .error)
        }
        let fresh = await AgentProcesses.scan()
        smart?.agents = fresh
    }

    /// Có nguồn AI nào dùng được ngay không (CLI đã cài hoặc API key).
    var aiCanAsk: Bool {
        switch aiProvider {
        case .api: return aiHasKey
        case .auto: return !AdvisorProvider.installedCLIs.isEmpty || aiHasKey
        default: return aiProvider.isInstalled
        }
    }

    /// Tải danh sách model của một nguồn (một lần mỗi phiên). Công cụ không có lệnh liệt kê thì dùng danh sách có sẵn.
    func loadAIModels(_ p: AdvisorProvider) async {
        guard aiModelOptions[p.rawValue] == nil else { return }
        aiModelOptions[p.rawValue] = AdvisorModels.builtin(for: p)   // hiện ngay, thay bằng danh sách thật khi tải xong
        let real = await AdvisorModels.list(for: p)
        if !real.isEmpty { aiModelOptions[p.rawValue] = real }
    }

    // MARK: Thực thi kế hoạch của AI

    /// Hành động hiện còn áp dụng được (đối chiếu lại với kết quả quét hiện tại, vì có thể đã dọn).
    func currentAction(_ id: String) -> AdvisorAction? {
        smart.flatMap { AdvisorPlanner.availableActions($0).first { $0.id == id } }
    }

    /// Các bước hiển thị: đã xong hoặc còn áp dụng được.
    var planRows: [AdvisorStep] {
        (advicePlan?.steps ?? []).compactMap { step in
            if planDone.contains(step.id) { return step }
            return currentAction(step.id).map { AdvisorStep(action: $0, reason: step.reason) }
        }
    }

    /// Các bước thay đổi máy (dọn vào Quarantine, kết thúc agent) chưa làm.
    /// "Áp dụng tất cả" chỉ gồm việc hoàn tác được; việc dọn bằng lệnh công cụ (không hoàn tác) phải bấm riêng từng cái.
    var pendingSafeSteps: [AdvisorStep] { planRows.filter { $0.action.kind != .review && $0.action.kind != .cleanTool && !planDone.contains($0.id) } }

    /// Làm một bước. Dọn luôn vào Quarantine (hoàn tác được), chỉ mục an toàn không dùng lệnh của công cụ, và không tự đóng app.
    func perform(_ step: AdvisorStep) async {
        let act = step.action
        switch act.kind {
        case .clean:
            var cleaned = false
            for id in ["system-junk", "dev-junk"] {
                guard var arr = results[id] else { continue }
                var any = false
                for i in arr.indices {
                    let match = arr[i].isAutoCleanable && AdvisorPlanner.sanitizedCategory(arr[i].category) == act.category
                    arr[i].selected = match; any = any || match
                }
                guard any else { continue }
                cleaned = true
                results[id] = arr
                await clean(id, mode: .quarantine, allowQuit: false)
            }
            // Không có gì để dọn (đã dọn rồi hoặc kết quả đã đổi): không được đánh dấu "Đã xong".
            guard cleaned else { notify(tr("Không còn mục nào để dọn trong nhóm này."), .warning); return }
            var r = smart ?? SmartScanResult()
            r.cleanup = results.values.flatMap { $0 }
            smart = r
        case .cleanTool:
            var cleaned = false
            for id in ["system-junk", "dev-junk"] {
                guard var arr = results[id] else { continue }
                var any = false
                for i in arr.indices {
                    let match = arr[i].safety == .safe && arr[i].command != nil && AdvisorPlanner.sanitizedCategory(arr[i].category) == act.category
                    arr[i].selected = match; any = any || match
                }
                guard any else { continue }
                cleaned = true
                results[id] = arr
                await clean(id, mode: .permanent, allowQuit: false)   // chạy lệnh của công cụ; không có Quarantine nên ghi đúng là xóa
            }
            guard cleaned else { notify(tr("Không còn mục nào để dọn trong nhóm này."), .warning); return }
            var r = smart ?? SmartScanResult()
            r.cleanup = results.values.flatMap { $0 }
            smart = r
        case .terminateAgents:
            for a in (smart?.flaggedAgents ?? []) { await terminateAgent(a) }
        case .review:
            let inSystem = (results["system-junk"] ?? []).contains { AdvisorPlanner.sanitizedCategory($0.category) == act.category }
            section = inSystem ? .systemJunk : .devJunk
            return   // chỉ mở trang, không tính là "đã xong"
        }
        planDone.insert(step.id)
    }

    /// Hỏi xác nhận rồi làm một bước.
    func confirmPerform(_ step: AdvisorStep) {
        let a = step.action
        switch a.kind {
        case .review: Task { await perform(step) }
        case .clean:
            confirmRequest = ConfirmRequest(
                title: trf("Dọn %@?", "\(a.category) · \(ByteFormat.string(Int64(a.megabytes) * 1_000_000))"),
                message: trf("Các mục sẽ được chuyển vào Quarantine và khôi phục được trong %@ ngày.", "\(retentionDays)"),
                confirmTitle: tr("Chuyển vào Quarantine"), symbol: "v.smartScan", action: { Task { await self.perform(step) } })
        case .cleanTool:
            let what = Set(((results["system-junk"] ?? []) + (results["dev-junk"] ?? []))
                .filter { $0.safety == .safe && $0.command != nil && AdvisorPlanner.sanitizedCategory($0.category) == a.category }.map(\.title)).sorted().joined(separator: ", ")
            confirmRequest = ConfirmRequest(
                title: trf("Dọn %@?", "\(a.category) · \(ByteFormat.string(Int64(a.megabytes) * 1_000_000))"),
                message: trf("Chạy lệnh dọn của chính công cụ (%@). Chỉ xóa dữ liệu có thể tạo lại hoặc tải lại. Không thể hoàn tác.", what),
                confirmTitle: tr("Dọn không hoàn tác"), destructive: true, symbol: "v.trash", action: { Task { await self.perform(step) } })
        case .terminateAgents:
            confirmRequest = ConfirmRequest(
                title: trf("Kết thúc %@ AI agent đáng ngờ?", "\(a.items)"),
                message: tr("Gửi tín hiệu thoát (SIGTERM) cho agent mồ côi hoặc ngốn CPU kéo dài. Công việc chưa lưu của chúng có thể mất."),
                confirmTitle: tr("Kết thúc"), destructive: true, symbol: "v.warn", action: { Task { await self.perform(step) } })
        }
    }

    /// Làm lần lượt mọi bước thay đổi máy trong kế hoạch, sau một lần xác nhận.
    func confirmApplyAll() {
        let steps = pendingSafeSteps
        guard !steps.isEmpty else { return }
        let lines = steps.map { s -> String in
            switch s.action.kind {
            case .clean, .cleanTool: return "• " + trf("Dọn %@ · %@", s.action.category, ByteFormat.string(Int64(s.action.megabytes) * 1_000_000))
            case .terminateAgents: return "• " + trf("Kết thúc %@ AI agent đáng ngờ", "\(s.action.items)")
            case .review: return ""
            }
        }.joined(separator: "\n")
        confirmRequest = ConfirmRequest(
            title: trf("Áp dụng %@ gợi ý?", "\(steps.count)"),
            message: lines + "\n\n" + tr("Mục dọn vào Quarantine (hoàn tác được). Agent bị gửi tín hiệu thoát, công việc chưa lưu của chúng có thể mất."),
            confirmTitle: tr("Áp dụng"), destructive: steps.contains { $0.action.kind == .terminateAgents }, symbol: "v.smartScan",
            action: { Task { for s in steps { await self.perform(s) } } })
    }

    /// Chỉ để chụp tài liệu/kiểm tra giao diện (VUTIDY_FAKE_ADVICE=1): dựng kế hoạch mẫu từ hành động thật, không gọi AI.
    func installFakeAdvice() {
        guard let r = smart else { return }
        let acts = AdvisorPlanner.availableActions(r)
        let reasons = ["Largest safe group; moves to Quarantine so you can undo.", "Caches rebuild on their own; low risk.", "Needs your eyes first: open the page and check each item."]
        let steps = acts.prefix(4).enumerated().map { AdvisorStep(action: $1, reason: reasons[$0 % reasons.count]) }
        advicePlan = AdvisorPlan(summary: "Free space is getting low. Clean the safe groups first, then review the rest by hand.", steps: Array(steps))
        advice = advicePlan?.summary; adviceSource = "Claude Code"
        Self.devScrollToBottom(after: 1.5)   // chụp được thẻ kế hoạch
    }

    /// Chỉ để chụp màn hình/kiểm tra giao diện (VUTIDY_FAKE_ADVICE, VUTIDY_SCROLL_BOTTOM): cuộn vùng cuộn lớn nhất của mỗi cửa sổ xuống đáy.
    static func devScrollToBottom(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            func scrollViews(_ v: NSView) -> [NSScrollView] { (v as? NSScrollView).map { [$0] } ?? [] + v.subviews.flatMap(scrollViews) }
            for w in NSApp.windows { if let c = w.contentView, let sv = scrollViews(c).max(by: { $0.frame.height < $1.frame.height }), let d = sv.documentView {
                sv.contentView.scroll(to: NSPoint(x: 0, y: d.isFlipped ? max(0, d.bounds.height - sv.contentView.bounds.height) : 0)); sv.reflectScrolledClipView(sv.contentView)
            } }
        }
    }

    var aiPayload: AdvisorInput? {
        guard let r = smart else { return nil }
        return ScanAdvisor.makeInput(r, diskTotal: snapshot?.disk.total ?? 0, diskFree: snapshot?.disk.availableImportant ?? 0)
    }

    func askAdvisor() async {
        guard aiAdvisorEnabled, let input = aiPayload, !adviceLoading else { return }
        guard let result = smart else { return }
        adviceLoading = true; adviceError = nil; adviceStatus = nil; adviceInspected = []; adviceDetails = nil
        defer { adviceLoading = false; adviceStatus = nil }
        do {
            let deep = try await ScanAdvisor.adviseDeep(input, result: result, provider: aiProvider, models: aiModels, language: L10n.current.nativeName,
                                                        deep: aiDeepDive, onStatus: { g in Task { @MainActor in self.adviceStatus = g } })
            let a = deep.answer
            adviceInspected = deep.inspected; adviceDetails = deep.details
            // AI trả JSON {summary, actions}. Đọc được thì hiện kế hoạch bấm-được; không thì hiện nguyên văn.
            let plan = smart.flatMap { AdvisorPlanner.parse(a.text, available: AdvisorPlanner.availableActions($0)) }
            advicePlan = plan; planDone = []
            advice = (plan?.summary.isEmpty == false ? plan?.summary : nil) ?? (plan == nil ? a.text : nil)
            adviceSource = a.provider.displayName        } catch let e as ScanAdvisor.AdvisorError {
            advice = nil; adviceSource = nil
            switch e {
            case .noKey: adviceError = tr("Chưa có API key. Thêm trong Cài đặt → Dọn dẹp.")
            case .http(let code, let msg): adviceError = trf("AI trả lỗi %@. %@", "\(code)", msg)
            case .empty: adviceError = tr("AI không trả về nội dung.")
            case .network(let m): adviceError = trf("Không kết nối được: %@", m)
            case .noProvider: adviceError = tr("Không tìm thấy công cụ AI nào dùng được. Cài và đăng nhập Claude Code, Codex hoặc Antigravity, hoặc thêm API key trong Cài đặt.")
            case .notLoggedIn(let n): adviceError = trf("%@ chưa đăng nhập. Mở %@ trong terminal và đăng nhập, rồi thử lại.", n, n)
            case .cli(let n, let d): adviceError = trf("%@ chạy lỗi: %@", n, d)
            }
        } catch { advice = nil; adviceError = error.localizedDescription }
    }
}
