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
    static let lastSelectedTool = "lastSelectedTool"
    static let annotationLineWidth = "annotationLineWidth"
    static let annotationFontSize = "annotationFontSize"
    static let annotationColor = "annotationColor"
    static let launchAtLogin = "launchAtLogin"
    static let jpegQuality = "jpegQuality"
    static let hasCompletedOnboarding = "hasCompletedOnboarding"
    static let enterAction = "enterAction"
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
    static let hotkeyChanged = Notification.Name("com.chuer.snap2.hotkeyChanged")
    static let annotationToolChanged = Notification.Name("com.chuer.snap2.annotationToolChanged")
    static let settingsChanged = Notification.Name("com.chuer.snap2.settingsChanged")
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
