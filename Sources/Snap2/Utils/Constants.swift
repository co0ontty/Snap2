import AppKit
import Carbon.HIToolbox

// MARK: - App Info

enum AppInfo {
    static let name = "Snap²"
    static let bundleID = "com.chuer.snap2"

    /// 当前进程的 bundle identifier，取不到时回退到硬编码值。
    /// 抽出来避免 CaptureManager / RecordingManager 重复同一段 fallback。
    static var currentBundleID: String {
        Bundle.main.bundleIdentifier ?? bundleID
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }
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
    static let hotkeyKeyCode = "hotkeyKeyCode"
    static let hotkeyModifiers = "hotkeyModifiers"
    /// 录屏热键（与截图热键独立配置，默认 ⌃⇧R）
    static let recordingHotkeyKeyCode = "recordingHotkeyKeyCode"
    static let recordingHotkeyModifiers = "recordingHotkeyModifiers"
    /// 录屏是否抓取系统音频（默认 true）
    static let recordingCapturesSystemAudio = "recordingCapturesSystemAudio"
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
    /// 标注工具栏上次选中的颜色（在 AnnotationPalette.colors 中的索引）
    static let annotationColorIndex = "annotationColorIndex"
    /// 标注工具栏上次选中的线宽（LineWidthLevel.rawValue）
    static let annotationLineWidth = "annotationLineWidth"
    /// 标注工具栏上次选中的工具（AnnotationToolType.rawValue）
    static let annotationTool = "annotationTool"
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

/// 标注工具栏的颜色 / 线宽偏好持久化。
/// 颜色以"在 AnnotationPalette.colors 中的索引"持久化，结构简单且不依赖颜色空间序列化。
enum AnnotationPreferences {
    static func loadColor() -> NSColor {
        let defaults = UserDefaults.standard
        // object(forKey:) != nil 区分 "用户存过 0" 与 "从未存过"
        guard defaults.object(forKey: UDKey.annotationColorIndex) != nil else {
            return AnnotationPalette.colors[0]
        }
        let idx = defaults.integer(forKey: UDKey.annotationColorIndex)
        let palette = AnnotationPalette.colors
        guard idx >= 0, idx < palette.count else { return palette[0] }
        return palette[idx]
    }

    static func saveColor(_ color: NSColor) {
        guard let idx = AnnotationPalette.colors.firstIndex(where: { $0.isEqualSrgb(color) }) else {
            // 不在调色板里的颜色（理论上不会发生）就不写，避免污染配置
            return
        }
        UserDefaults.standard.set(idx, forKey: UDKey.annotationColorIndex)
    }

    static func loadLineWidth() -> LineWidthLevel {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: UDKey.annotationLineWidth) != nil else {
            return .medium
        }
        let raw = CGFloat(defaults.double(forKey: UDKey.annotationLineWidth))
        return LineWidthLevel.allCases.first { $0.rawValue == raw } ?? .medium
    }

    static func saveLineWidth(_ width: CGFloat) {
        UserDefaults.standard.set(Double(width), forKey: UDKey.annotationLineWidth)
    }

    static func loadTool() -> AnnotationToolType {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: UDKey.annotationTool) != nil else {
            return .arrow
        }
        let raw = defaults.integer(forKey: UDKey.annotationTool)
        return AnnotationToolType(rawValue: raw) ?? .arrow
    }

    static func saveTool(_ tool: AnnotationToolType) {
        UserDefaults.standard.set(tool.rawValue, forKey: UDKey.annotationTool)
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
    /// 选区外的暗色蒙版填充。截图与录屏取景共用。
    static let overlayColor: NSColor = NSColor.black.withAlphaComponent(0.3)
}
