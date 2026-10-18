import AppKit
import ServiceManagement
import Combine

@MainActor final class LoginService: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var needsApproval = false
    @Published private(set) var error: String?
    init() { refresh() }
    func refresh() {
        let status = SMAppService.mainApp.status
        enabled = status == .enabled || status == .requiresApproval
        needsApproval = status == .requiresApproval
    }
    func setEnabled(_ value: Bool) {
        error = nil
        do {
            if value { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch { self.error = "Não foi possível alterar a inicialização: \(error.localizedDescription)" }
        refresh()
    }
    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}
