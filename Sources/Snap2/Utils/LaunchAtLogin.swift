import Foundation
import ServiceManagement

// MARK: - 开机自启动管理
/// 使用 SMAppService API 管理应用的登录项
enum LaunchAtLogin {

    static var isEnabled: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            if newValue { enable() } else { disable() }
        }
    }

    @discardableResult
    static func enable() -> Bool {
        do {
            try SMAppService.mainApp.register()
            return true
        } catch {
            NSLog("[LaunchAtLogin] 启用开机自启动失败: \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    static func disable() -> Bool {
        do {
            try SMAppService.mainApp.unregister()
            return true
        } catch {
            NSLog("[LaunchAtLogin] 禁用开机自启动失败: \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    static func toggle() -> Bool {
        isEnabled ? disable() : enable()
    }
}
