import AppKit
import Carbon.HIToolbox

// MARK: - App Info

enum AppInfo {
    static let name = "Snap²"
    static let bundleID = "com.chuer.snap2"
}

// MARK: - Hotkey

enum DefaultHotkey {
    /// Region capture: Ctrl + Shift + A
    static let regionCaptureKeyCode: UInt16 = UInt16(kVK_ANSI_A)
    static let regionCaptureModifiers: NSEvent.ModifierFlags = [.control, .shift]

    /// Region recording: Ctrl + Shift + R
    static let regionRecordingKeyCode: UInt16 = UInt16(kVK_ANSI_R)
    static let regionRecordingModifiers: NSEvent.ModifierFlags = [.control, .shift]
}

// MARK: - UserDefaults Keys

enum UDKey {
    static let saveDirectory = "saveDirectory"
    static let imageFormat = "imageFormat"
    static let includesCursor = "includesCursor"
    static let playSoundOnCapture = "playSoundOnCapture"
    static let copyToClipboard = "copyToClipboard"
    static let hotkeyKeyCode = "hotkeyKeyCode"
    static let hotkeyModifiers = "hotkeyModifiers"
    /// 录屏热键（与截图热键独立配置，默认 ⌃⇧R）
    static let recordingHotkeyKeyCode = "recordingHotkeyKeyCode"
    static let recordingHotkeyModifiers = "recordingHotkeyModifiers"
    /// 录屏是否抓取系统音频（默认 true）
    static let recordingCapturesSystemAudio = "recordingCapturesSystemAudio"
    static let lastSelectedTool = "lastSelectedTool"
    static let annotationLineWidth = "annotationLineWidth"
    static let annotationFontSize = "annotationFontSize"
    static let annotationColor = "annotationColor"
    static let launchAtLogin = "launchAtLogin"
    static let jpegQuality = "jpegQuality"
    static let hasCompletedOnboarding = "hasCompletedOnboarding"
    static let enterAction = "enterAction"
    /// 上次检查更新的时间戳（秒）
    static let lastUpdateCheckAt = "lastUpdateCheckAt"
    /// 上次检测到的最新版本号（不含 v 前缀），用于菜单栏角标持久化
    static let lastKnownLatestVersion = "lastKnownLatestVersion"
    /// 是否订阅 Beta（commit）更新通道
    static let betaUpdates = "betaUpdates"
}

/// 回车键行为
enum EnterAction: String {
    case copy
    case save

    static var current: EnterAction {
        let raw = UserDefaults.standard.string(forKey: UDKey.enterAction) ?? "copy"
        return EnterAction(rawValue: raw) ?? .copy
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let captureRequested = Notification.Name("com.chuer.snap2.captureRequested")
    static let captureCompleted = Notification.Name("com.chuer.snap2.captureCompleted")
    static let captureCancelled = Notification.Name("com.chuer.snap2.captureCancelled")
    /// 用户触发"开始区域录屏"——菜单或全局热键。AppDelegate 兜底权限检查后转给 RecordingManager。
    static let recordingRequested = Notification.Name("com.chuer.snap2.recordingRequested")
    /// 用户在录屏中再次按热键 / 点停止 / Esc 确认 —— 让全局热键与悬浮控制面板共享一份停止信号。
    static let recordingStopRequested = Notification.Name("com.chuer.snap2.recordingStopRequested")
    static let recordingStarted = Notification.Name("com.chuer.snap2.recordingStarted")
    static let recordingFinished = Notification.Name("com.chuer.snap2.recordingFinished")
    static let hotkeyChanged = Notification.Name("com.chuer.snap2.hotkeyChanged")
    static let annotationToolChanged = Notification.Name("com.chuer.snap2.annotationToolChanged")
    static let settingsChanged = Notification.Name("com.chuer.snap2.settingsChanged")
    static let updateAvailable = Notification.Name("com.chuer.snap2.updateAvailable")
    /// 一次更新检查完成且当前已是最新版本（用于清除 UI 角标）
    static let updateNotAvailable = Notification.Name("com.chuer.snap2.updateNotAvailable")
    /// 外部 UI 请求触发一次手动更新检查（由菜单栏控制器统一接管 alert 流程）
    static let updateCheckRequested = Notification.Name("com.chuer.snap2.updateCheckRequested")
    /// 用户在设置中切换了 Beta 更新通道
    static let betaChannelChanged = Notification.Name("com.chuer.snap2.betaChannelChanged")
}

// MARK: - Drawing Defaults

enum DrawingDefaults {
    static let lineWidth: CGFloat = 2.0
    static let arrowLineWidth: CGFloat = 2.0
    static let highlightAlpha: CGFloat = 0.35
    static let fontSize: CGFloat = 14.0
    static let cornerRadius: CGFloat = 4.0
    static let handleSize: CGFloat = 8.0

    static let strokeColor: NSColor = .systemRed
    static let fillColor: NSColor = .clear
    static let textColor: NSColor = .systemRed
    static let highlightColor: NSColor = .systemYellow

    static let selectionBorderColor: NSColor = .systemBlue
    static let selectionBorderWidth: CGFloat = 1.0
    static let overlayColor: NSColor = NSColor.black.withAlphaComponent(0.3)
}
