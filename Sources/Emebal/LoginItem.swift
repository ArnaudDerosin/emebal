import Observation
import ServiceManagement

/// Opens Emebal when the user logs in. macOS keeps this setting itself, in
/// System Settings → General → Login Items, so it isn't stored in UserDefaults.
@MainActor
@Observable
final class LoginItem {
    static let shared = LoginItem()

    private(set) var isEnabled = false

    private init() {
        refresh()
    }

    /// Reads the current state, which the user can also change in System Settings.
    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Usually the user has to approve it in System Settings first.
            SMAppService.openSystemSettingsLoginItems()
        }
        refresh()
        if enabled, SMAppService.mainApp.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }
}
