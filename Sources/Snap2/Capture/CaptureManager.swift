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

        // 异步冻结每屏当前画面：覆盖层先以暗色蒙版示人，
        // 拿到全屏快照后再 setFrozenImage 让选区下方变成"凝固"的桌面，
        // 避免用户慢慢框选时动态内容（视频/动画）已被划过去。
        let snapshot = overlayWindows
        let overlayWindowIDs = overlayWindows.map { CGWindowID($0.windowNumber) }
        Task { @MainActor in
            for overlay in snapshot {
                let screen = overlay.targetScreen
                if let image = await self.captureFullScreen(screen: screen, excludingWindowIDs: overlayWindowIDs) {
                    (overlay.contentView as? SelectionView)?.setFrozenImage(image)
                }
            }
        }
    }

    /// 捕获指定屏幕的整屏画面，用于"冻结"桌面。
    /// 调用方负责在主 actor 收集 overlay 的 windowNumber。
    private func captureFullScreen(screen: NSScreen, excludingWindowIDs overlayWindowIDs: [CGWindowID]) async -> NSImage? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let scDisplay = content.displays.first(where: { display in
                display.displayID == screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            }) ?? content.displays.first else { return nil }

            let selfBundleID = Bundle.main.bundleIdentifier ?? AppInfo.bundleID
            let excludeWindows = content.windows.filter { w in
                overlayWindowIDs.contains(CGWindowID(w.windowID)) ||
                w.owningApplication?.bundleIdentifier == selfBundleID
            }
            let filter = SCContentFilter(display: scDisplay, excludingWindows: excludeWindows)

            let config = SCStreamConfiguration()
            let scale = screen.backingScaleFactor
            config.width = Int(screen.frame.width * scale)
            config.height = Int(screen.frame.height * scale)
            config.scalesToFit = false
            config.showsCursor = false

            let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            return NSImage(cgImage: cgImage, size: screen.frame.size)
        } catch {
            NSLog("[CaptureManager] 全屏冻结失败: \(error.localizedDescription)")
            return nil
        }
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
                // NSImage 非 Sendable，在 MainActor 内构造避免跨 actor 边界传递。
                // size 必须是逻辑点尺寸（rect.size）而非像素尺寸，否则 NSImage 会把
                // 高分辨率 CGImage 当成 1× 来缩放，导致 Retina 屏上的实时预览出现
                // 插值模糊。用 rect.size 让 NSImage 知道这是个 backing scale 为
                // (cgImage.width/rect.width) 倍的高分图。
                await MainActor.run {
                    let image = NSImage(cgImage: cgImage, size: rect.size)
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
