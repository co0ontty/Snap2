import AppKit
import CoreGraphics
import CoreVideo
import ScreenCaptureKit

/// 屏幕截图管理器（单例）
final class CaptureManager {

    static let shared = CaptureManager()
    private init() {}

    private var overlayWindows: [OverlayWindow] = []
    private(set) var isCapturing = false
    private var didPushCaptureCursor = false
    private struct CaptureTarget {
        let screen: NSScreen
        let displayID: CGDirectDisplayID?
        let scale: CGFloat
        let frameSize: NSSize
    }
    private struct FrozenCapture {
        let cgImage: CGImage
        let pointSize: NSSize
    }
    /// 当前被"重新标注"的钉图——会在编辑期间隐藏，结束后再 orderFront 回来
    private var pinBeingEdited: PinnedImageWindow?
    /// 本次会话结束时是否要"销毁"被编辑的钉图（而非还原）。
    /// 成功路径（save / copy / pin / record）会先置 true 再 finishAndClose；
    /// 取消路径（Esc / 关闭按钮）保持 false，钉图照旧 orderFront 回来。
    private var shouldDiscardEditedPinOnClose = false

    // MARK: - 开始截图

    func startCapture() {
        guard !isCapturing else { return }
        // 与录屏互斥：录屏正在进行（取景或写盘）期间禁止启动截图，避免视频会话被遮罩干扰
        guard !RecordingManager.shared.isActive else {
            NSLog("[CaptureManager] startCapture 被忽略：RecordingManager 正在 active")
            return
        }
        isCapturing = true

        let screens = Self.screensPrioritizingMouseLocation()
        let targets = screens.map { screen in
            CaptureTarget(
                screen: screen,
                displayID: screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                scale: screen.backingScaleFactor,
                frameSize: screen.frame.size
            )
        }
        guard !targets.isEmpty else {
            isCapturing = false
            return
        }

        // 先在不激活本 App、不盖 overlay 的状态下冻结桌面。
        // 这样全局热键触发时，鼠标仍然悬停在原应用上，tooltip / hover popover
        // 不会因为 Snap² 抢焦点或覆盖鼠标命中目标而先消失。
        Task { @MainActor in
            var prepared: [(target: CaptureTarget, frozen: FrozenCapture?)] = []
            for target in targets {
                if let snap = await self.captureFullScreen(
                    displayID: target.displayID,
                    scale: target.scale,
                    frameSize: target.frameSize)
                {
                    prepared.append((
                        target: target,
                        frozen: FrozenCapture(cgImage: snap.cgImage, pointSize: snap.pointSize)
                    ))
                } else {
                    prepared.append((target: target, frozen: nil))
                }
            }
            self.presentCaptureOverlays(prepared)
        }
    }

    private static func screensPrioritizingMouseLocation() -> [NSScreen] {
        let screens = NSScreen.screens
        let mouseLocation = NSEvent.mouseLocation
        guard let hoveredScreen = screens.first(where: { $0.frame.contains(mouseLocation) }) else {
            return screens
        }
        return [hoveredScreen] + screens.filter { $0 !== hoveredScreen }
    }

    @MainActor
    private func presentCaptureOverlays(_ prepared: [(target: CaptureTarget, frozen: FrozenCapture?)]) {
        guard isCapturing, overlayWindows.isEmpty else { return }

        NSCursor.crosshair.push()
        didPushCaptureCursor = true

        for item in prepared {
            let overlay = OverlayWindow(screen: item.target.screen)
            if let frozen = item.frozen {
                (overlay.contentView as? SelectionView)?.setFrozenSnapshot(
                    cgImage: frozen.cgImage,
                    pointSize: frozen.pointSize
                )
            }
            overlay.makeKeyAndOrderFront(nil)
            overlayWindows.append(overlay)
        }

        NSApp.activate(ignoringOtherApps: true)
        overlayWindows.first?.makeKey()
    }

    /// 捕获指定屏幕的整屏画面，用于"冻结"桌面。
    /// 调用方负责在主 actor 上从 NSScreen 提取 displayID/scale/frameSize 标量后再传进来——
    /// 把 NSScreen 留在主 actor，函数内部只跟值类型打交道，跨 await 边界不会引发并发问题。
    /// 返回原始像素 CGImage 与对应的逻辑点尺寸——上层不再走 NSImage round-trip，
    /// 避免 cgImage(forProposedRect:) 在某些机型/版本上把高分图重采样回点级分辨率。
    private func captureFullScreen(displayID: CGDirectDisplayID?,
                                   scale: CGFloat,
                                   frameSize: NSSize) async
        -> (cgImage: CGImage, pointSize: NSSize)?
    {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let scDisplay = content.displays.first(where: { display in
                display.displayID == displayID
            }) ?? content.displays.first else { return nil }

            // 按 application 排除整个 Snap2 进程，而不是按窗口列表过滤。
            // 旧实现 `content.windows.filter { ... }` 只能匹配 SCShareableContent 抓
            // 快照那一刻已经在 WindowServer 注册为 on-screen 的窗口；overlay 在
            // `makeKeyAndOrderFront` 之后到真正"上屏"之间有几帧延迟（外接显示器尤其
            // 明显），这段时间内拉到的 content.windows 不包含 overlay → overlay 不被
            // 排除 → SCK 实际截图时 overlay 已经把 30% 黑色蒙版画上去，被一起截进
            // frozenCGImage，结果就是"桌面截图偏暗"。
            // 改为按 application 排除后，policy 在 capture 时生效，无论 overlay 何时
            // 上屏都不会进入截图。
            let selfBundleID = AppInfo.currentBundleID
            let excludeApps = content.applications.filter {
                $0.bundleIdentifier == selfBundleID
            }
            let filter = SCContentFilter(display: scDisplay,
                                          excludingApplications: excludeApps,
                                          exceptingWindows: [])

            let config = SCStreamConfiguration()
            config.width = Int(frameSize.width * scale)
            config.height = Int(frameSize.height * scale)
            config.scalesToFit = false
            config.showsCursor = false
            // 显式保留广色域：默认值在不同 macOS 版本/显示器上不一致，
            // 不指定时部分机型会回落到 sRGB，导致 P3 屏幕上的饱和色变暗变灰。
            config.colorSpaceName = CGColorSpace.displayP3
            config.pixelFormat = kCVPixelFormatType_32BGRA

            let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            return (cgImage, frameSize)
        } catch {
            NSLog("[CaptureManager] 全屏冻结失败: \(error.localizedDescription)")
            return nil
        }
    }

    func cancelCapture() {
        closeAllOverlays()
    }

    // MARK: - 钉图重新标注

    /// 把钉图作为画布重新进入标注模式：暂时隐藏原钉图，开一个仅覆盖钉图所在屏幕的
    /// overlay，把钉图图片直接当作 capturedImage 灌进 SelectionView，跳过选区阶段。
    /// Enter / Esc 走原始流程：
    ///   - 成功路径（save/copy/pin/record） → 旧钉图销毁
    ///   - 取消路径（Esc / 关闭按钮）       → 旧钉图 orderFront 回来
    /// 由 finishAndClose / finishAndCloseDiscardingEditedPin 的语义切换决定。
    /// - Parameter startTool: 可选起始工具——从钉图 hover 工具栏点哪个工具进入就传哪个。
    func editPin(_ pin: PinnedImageWindow,
                 startTool: AnnotationToolType? = nil) {
        guard !isCapturing else { return }

        // 1. 选钉图所在屏幕（取相交面积最大的；保底用主屏）
        let pinFrame = pin.frame
        let screen = NSScreen.screens.max { a, b in
            a.frame.intersection(pinFrame).area < b.frame.intersection(pinFrame).area
        } ?? NSScreen.main ?? NSScreen.screens.first
        guard let targetScreen = screen else { return }

        // 2. 隐藏原钉图，标记待恢复（默认走"取消路径"逻辑；成功路径会另置 flag）
        pinBeingEdited = pin
        shouldDiscardEditedPinOnClose = false
        pin.orderOut(nil)

        // 3. 启动 overlay（同 startCapture，但只一块屏幕）
        isCapturing = true
        NSCursor.crosshair.push()
        didPushCaptureCursor = true
        let overlay = OverlayWindow(screen: targetScreen)
        overlay.makeKeyAndOrderFront(nil)
        overlayWindows.append(overlay)
        NSApp.activate(ignoringOtherApps: true)
        overlay.makeKey()

        // 4. 钉图屏幕坐标 → SelectionView 局部坐标（overlay 与屏幕等大同源）
        let local = NSRect(
            x: pinFrame.origin.x - targetScreen.frame.origin.x,
            y: pinFrame.origin.y - targetScreen.frame.origin.y,
            width: pinFrame.width,
            height: pinFrame.height
        )

        // 5. 直接进入 annotating，跳过选区阶段。
        //    优先把原始 CGImage 一并传过去，让 SelectionView 的像素操作走 CGImage 直链；
        //    NSImage.cgImage(forProposedRect:) 的兜底由 startPinEdit 内部处理。
        (overlay.contentView as? SelectionView)?.startPinEdit(
            image: pin.currentImage,
            cgImage: pin.currentCGImage,
            selectionInView: local,
            startTool: startTool
        )
    }

    // MARK: - 内联截图（不关闭覆盖层，回调图片给 SelectionView）

    /// 内联截图：把抓到的 CGImage 直接抛回（保留原始像素分辨率），不做 NSImage 包装。
    /// 上层负责自己持有 CGImage 引用做后续 crop/render，避免 cgImage(forProposedRect:)
    /// 在某些机型/macOS 版本下把高分图重采样回点级分辨率（症状：分辨率特别低 + 模糊）。
    func captureInline(rect: NSRect, screen: NSScreen, completion: @escaping (CGImage?, NSSize) -> Void) {
        let mainScreenHeight = NSScreen.screens.first?.frame.height ?? 0
        let captureRect = CGRect(
            x: rect.origin.x,
            y: mainScreenHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )

        // NSScreen 非 Sendable，先取出需要的标量再进 Task
        let screenDisplayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        let backingScale = screen.backingScaleFactor
        let pointSize = rect.size

        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

                guard let scDisplay = content.displays.first(where: { display in
                    display.displayID == screenDisplayID
                }) ?? content.displays.first else {
                    await MainActor.run { completion(nil, pointSize) }
                    return
                }

                // 排除自身所有窗口——按 application 而非按窗口列表，理由见 captureFullScreen
                let selfBundleID = AppInfo.currentBundleID
                let excludeApps = content.applications.filter {
                    $0.bundleIdentifier == selfBundleID
                }
                let filter = SCContentFilter(display: scDisplay,
                                              excludingApplications: excludeApps,
                                              exceptingWindows: [])

                let config = SCStreamConfiguration()
                config.sourceRect = captureRect
                config.width = Int(captureRect.width * backingScale)
                config.height = Int(captureRect.height * backingScale)
                config.scalesToFit = false
                config.showsCursor = false
                // 与全屏冻结路径保持一致，强制广色域+BGRA，避免颜色失真
                config.colorSpaceName = CGColorSpace.displayP3
                config.pixelFormat = kCVPixelFormatType_32BGRA

                let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                await MainActor.run {
                    completion(cgImage, pointSize)
                }
            } catch {
                NSLog("[CaptureManager] 截图失败: \(error.localizedDescription)")
                await MainActor.run { completion(nil, pointSize) }
            }
        }
    }

    // MARK: - 完成并关闭

    /// 取消语义：Esc / 关闭按钮调用。若处于"编辑钉图"流程，旧钉图 orderFront 回来。
    func finishAndClose() {
        closeAllOverlays()
    }

    /// 成功语义：复制 / 保存 / 钉桌面 / 录制选区 调用。
    /// 若处于"编辑钉图"流程，旧钉图被销毁（不再 orderFront），避免桌面同时出现
    /// 老版本 + 新结果（save 文件、新 pin 等）的重复钉图。
    func finishAndCloseDiscardingEditedPin() {
        shouldDiscardEditedPinOnClose = true
        closeAllOverlays()
    }

    private func closeAllOverlays() {
        if didPushCaptureCursor {
            NSCursor.pop()
            didPushCaptureCursor = false
        }
        for window in overlayWindows {
            (window.contentView as? SelectionView)?.prepareForClose()
            window.contentView = nil
            window.orderOut(nil)
        }
        overlayWindows.removeAll()
        isCapturing = false

        // 编辑期间隐藏的钉图：根据 shouldDiscardEditedPinOnClose 决定还原还是销毁。
        if let pin = pinBeingEdited {
            if shouldDiscardEditedPinOnClose {
                // 销毁旧钉图——orderOut 即可（PinnedImageWindow 的 allPins 静态强引用
                // 由其内部 dismissAnimated 维护，这里直接 orderOut + 主动从 allPins 移除）。
                pin.discardForReplacement()
            } else {
                pin.orderFront(nil)
            }
            pinBeingEdited = nil
        }
        shouldDiscardEditedPinOnClose = false
    }
}

private extension NSRect {
    var area: CGFloat { max(0, width) * max(0, height) }
}
