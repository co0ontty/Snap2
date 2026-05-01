import AppKit
import CoreGraphics
import ScreenCaptureKit

/// 屏幕截图管理器（单例）
final class CaptureManager {

    static let shared = CaptureManager()
    private init() {}

    private var overlayWindows: [OverlayWindow] = []
    private(set) var isCapturing = false

    // MARK: - 开始截图

    func startCapture() {
        guard !isCapturing else { return }
        isCapturing = true
        NSCursor.crosshair.push()

        for screen in NSScreen.screens {
            let overlay = OverlayWindow(screen: screen)
            overlay.makeKeyAndOrderFront(nil)
            overlayWindows.append(overlay)
        }

        NSApp.activate(ignoringOtherApps: true)
        overlayWindows.first?.makeKey()
    }

    func cancelCapture() {
        closeAllOverlays()
    }

    // MARK: - 内联截图（不关闭覆盖层，回调图片给 SelectionView）

    func captureInline(rect: NSRect, screen: NSScreen, completion: @escaping (NSImage?) -> Void) {
        let overlayWindowIDs = overlayWindows.map { CGWindowID($0.windowNumber) }

        let mainScreenHeight = NSScreen.screens.first?.frame.height ?? 0
        let captureRect = CGRect(
            x: rect.origin.x,
            y: mainScreenHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )

        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

                guard let scDisplay = content.displays.first(where: { display in
                    display.displayID == screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
                }) ?? content.displays.first else {
                    await MainActor.run { completion(nil) }
                    return
                }

                // 排除自身所有窗口
                let selfBundleID = Bundle.main.bundleIdentifier ?? AppInfo.bundleID
                let excludeWindows = content.windows.filter { w in
                    overlayWindowIDs.contains(CGWindowID(w.windowID)) ||
                    w.owningApplication?.bundleIdentifier == selfBundleID
                }

                let filter = SCContentFilter(display: scDisplay, excludingWindows: excludeWindows)

                let config = SCStreamConfiguration()
                config.sourceRect = captureRect
                config.width = Int(captureRect.width * screen.backingScaleFactor)
                config.height = Int(captureRect.height * screen.backingScaleFactor)
                config.scalesToFit = false
                config.showsCursor = false

                let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                // NSImage 非 Sendable，在 MainActor 内构造避免跨 actor 边界传递
                await MainActor.run {
                    let image = NSImage(
                        cgImage: cgImage,
                        size: NSSize(width: cgImage.width, height: cgImage.height)
                    )
                    completion(image)
                }
            } catch {
                NSLog("[CaptureManager] 截图失败: \(error.localizedDescription)")
                await MainActor.run { completion(nil) }
            }
        }
    }

    // MARK: - 完成并关闭

    func finishAndClose() {
        closeAllOverlays()
    }

    private func closeAllOverlays() {
        NSCursor.pop()
        for window in overlayWindows {
            (window.contentView as? SelectionView)?.prepareForClose()
            window.contentView = nil
            window.orderOut(nil)
        }
        overlayWindows.removeAll()
        isCapturing = false
    }
}
