import AppKit
import Foundation

/// 系统设置里要引导用户去授权的具体隐私面板。
///
/// 用 macOS 13+ 新版 System Settings 的 URL scheme：
/// `x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?<anchor>`
/// 旧版 `com.apple.preference.security` 在 Ventura 之后已经不被推荐，部分系统下
/// 会跳到「隐私与安全性」根页而不是具体分类。
enum PermissionPanel: String, CaseIterable, Sendable {
    case screenRecording = "Privacy_ScreenCapture"
    case accessibility = "Privacy_Accessibility"

    /// 中文标题。直接拼到「以授予……权限」文案里。
    var title: String {
        switch self {
        case .screenRecording: return "屏幕录制"
        case .accessibility: return "辅助功能"
        }
    }

    var settingsURL: URL {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(rawValue)") else {
            preconditionFailure("无效的系统设置 URL: \(rawValue)")
        }
        return url
    }
}
