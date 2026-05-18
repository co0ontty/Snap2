import AppKit
import Foundation

/// 描述要引导用户授权的"宿主应用"——也就是当前进程自己。
/// 把 displayName / bundleURL / icon 三件套打包，方便气泡的拖拽行、文案统一用一份数据。
struct PermissionHostApp: Sendable {
    let displayName: String
    let bundleURL: URL
    let icon: NSImage

    /// 从 Bundle.main 取当前进程信息。icon 通过 NSWorkspace 反查 .app 的图标资源，
    /// 这样 dev/debug/release 三种 bundle 名变化都能拿到正确图标。
    static func current(bundle: Bundle = .main) -> PermissionHostApp {
        let bundleURL = bundle.bundleURL
        let icon = NSWorkspace.shared.icon(forFile: bundleURL.path)
        // 拖拽行里图标占 22×22，气泡内不需要超大尺寸；这里先归一到 48 给上游随便缩。
        icon.size = NSSize(width: 48, height: 48)
        return PermissionHostApp(
            displayName: AppInfo.name,
            bundleURL: bundleURL,
            icon: icon
        )
    }
}
