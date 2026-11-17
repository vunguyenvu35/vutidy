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

    var aiPayload: AdvisorInput? {
        guard let r = smart else { return nil }
        return ScanAdvisor.makeInput(r, diskTotal: snapshot?.disk.total ?? 0, diskFree: snapshot?.disk.availableImportant ?? 0)
    }

    func askAdvisor() async {
        guard aiAdvisorEnabled, let input = aiPayload, !adviceLoading else { return }
        adviceLoading = true; adviceError = nil
        defer { adviceLoading = false }
        do {
            advice = try await ScanAdvisor.advise(input, model: aiModel.isEmpty ? ScanAdvisor.defaultModel : aiModel,
                                                  language: L10n.current.nativeName)
        } catch let e as ScanAdvisor.AdvisorError {
            advice = nil
            switch e {
            case .noKey: adviceError = tr("Chưa có API key. Thêm trong Cài đặt → Dọn dẹp.")
            case .http(let code, let msg): adviceError = trf("AI trả lỗi %@. %@", "\(code)", msg)
            case .empty: adviceError = tr("AI không trả về nội dung.")
            case .network(let m): adviceError = trf("Không kết nối được: %@", m)
            }
        } catch { advice = nil; adviceError = error.localizedDescription }
    }
}
