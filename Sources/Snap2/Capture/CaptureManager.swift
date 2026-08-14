import AppKit
import CoreGraphics
import CoreVideo
import ScreenCaptureKit

/// 屏幕截图管理器（单例）
final class CaptureManager {

    static let shared = CaptureManager()
    private init() {
        installModifierPreFreezeMonitor()
    }

    private var overlayWindows: [OverlayWindow] = []
    private(set) var isCapturing = false
    private var didPushCaptureCursor = false
    private struct CaptureTarget {
        let screen: NSScreen
        let displayID: CGDirectDisplayID?
        let scale: CGFloat
        let frameSize: NSSize
    }
    /// 当前被"重新标注"的钉图——会在编辑期间隐藏，结束后再 orderFront 回来
    private var pinBeingEdited: PinnedImageWindow?
    /// 本次会话结束时是否要"销毁"被编辑的钉图（而非还原）。
    /// 成功路径（save / copy / pin / record）会先置 true 再 finishAndClose；
    /// 取消路径（Esc / 关闭按钮）保持 false，钉图照旧 orderFront 回来。
    private var shouldDiscardEditedPinOnClose = false

    // MARK: - 修饰键预冻结（抢跑）

    /// 预冻结任务槽：修饰键按满那一刻后台发起，热键触发时一次性消费。
    private var preFreezeLock = NSLock()
    private var preFreeze: ParallelDisplayFreezer?
    /// NSEvent 监听 token（app 生命周期内存活，不移除）。
    private var flagsChangedMonitors: [Any?] = []
    /// 上一次 flagsChanged 时"我们关心的四个修饰键"的状态，用于上升沿检测。
    private var lastRelevantFlags: NSEvent.ModifierFlags = []

    /// 监听 flagsChanged：当修饰键状态在上升沿"恰好等于"截图热键的修饰键组合时
    /// （例如 Ctrl+Shift+A 的 Ctrl↓ → Shift↓ 完成、A 还没按下），立刻在后台并行冻结
    /// 所有显示器。
    ///
    /// 为什么要抢跑到修饰键阶段——热键 keyDown 才截图有两个赢不了的比赛：
    ///  a) Chrome / Electron 会把裸修饰键的 keydown 派发给网页，不少 hover UI
    ///     "按任意键就收起"；等 A 键 keyDown 到来时帧里早就没了；
    ///  b) Carbon 热键只吞 keyDown，松键产生的 keyUp / flagsChanged 仍会投递给
    ///     前台 app，慢机器 / 多屏下现场抓帧经常输给松键。
    /// 在修饰键按满的瞬间抓帧，a / b 两类消失事件都还没发生（或还没渲染上屏）。
    ///
    /// 权限前提：全局监听键盘类事件（flagsChanged）需要 app 被信任（辅助功能 /
    /// 输入监控）。未授权时系统静默不派发——监听器无害，授权后（无需重启）自动生效。
    /// 无屏幕录制权限时不装监听：CGDisplayCreateImage 只会返回 nil，白烧 CPU；
    /// 该权限授权后必须重启 app 才生效，所以启动时查一次就够。
    private func installModifierPreFreezeMonitor() {
        guard CGPreflightScreenCaptureAccess() else {
            NSLog("[CaptureManager] 预冻结未启用：缺少屏幕录制权限")
            return
        }
        let onFlags: (NSEvent) -> Void = { [weak self] event in
            guard let self else { return }
            let update = { self.relevantModifierFlagsChanged(to: event.modifierFlags) }
            // NSEvent 监听回调常规在主线程到达；万一不在，跳主线程处理
            // （NSScreen / RecordingManager 状态都只能主线程摸）。
            if Thread.isMainThread { update() } else { DispatchQueue.main.async(execute: update) }
        }
        flagsChangedMonitors.append(
            NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: onFlags)
        )
        flagsChangedMonitors.append(
            NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                onFlags(event)
                return event
            }
        )
    }

    /// flagsChanged 主线程处理：命中"上升沿 == 截图热键修饰键"才触发抢跑。
    private func relevantModifierFlagsChanged(to rawFlags: NSEvent.ModifierFlags) {
        let relevant: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        let current = rawFlags.intersection(relevant)
        let previous = lastRelevantFlags
        lastRelevantFlags = current

        // 热键可被用户改绑，在事件时刻实时取当前绑定；裸键热键无从预判，跳过。
        let target = HotkeyManager.shared.cocoaModifiers(for: .capture)
        guard !target.isEmpty, current == target, previous != current else { return }

        triggerPreFreeze()
    }

    /// 后台发起一次全显示器并行冻结，存入预冻结槽。
    private func triggerPreFreeze() {
        // overlay / 录屏进行中不需要也不该抢跑（画面里会有我们自己的 UI）。
        guard !isCapturing, !RecordingManager.shared.isActive else { return }

        let requests = NSScreen.screens.compactMap { screen -> ParallelDisplayFreezer.Request? in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                    as? CGDirectDisplayID else { return nil }
            return ParallelDisplayFreezer.Request(displayID: id, frameSize: screen.frame.size)
        }
        guard !requests.isEmpty else { return }

        let freezer = ParallelDisplayFreezer(requests: requests)
        preFreezeLock.lock()
        preFreeze = freezer
        preFreezeLock.unlock()

        // 抢跑帧描述的是"按下修饰键那一瞬"的世界，时效极短。没被热键消费掉
        // （用户只是按了同组合的其它快捷键）就尽快释放，避免多屏大图常驻内存。
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self, weak freezer] in
            guard let self, let freezer else { return }
            self.preFreezeLock.lock()
            if self.preFreeze === freezer { self.preFreeze = nil }
            self.preFreezeLock.unlock()
        }
    }

    /// 一次性取走"新鲜"的预冻结任务；过期或不存在返回 nil（并清槽）。
    private func takeFreshPreFreeze(maxAgeMilliseconds: Double) -> ParallelDisplayFreezer? {
        preFreezeLock.lock()
        defer { preFreezeLock.unlock() }
        guard let freezer = preFreeze, freezer.ageMilliseconds <= maxAgeMilliseconds else {
            preFreeze = nil
            return nil
        }
        preFreeze = nil
        return freezer
    }

    // MARK: - 开始截图

    /// 全屏冻结入口。**整条链路同步、零跳变**：热键回调（主线程）→ 同步通知 →
    /// 本方法 → 有界等待并行冻结 → 盖 overlay。中间没有任何 `DispatchQueue.main.async` /
    /// `Task { @MainActor }` 跳变——每一跳都会让主 runloop 多转一圈，pump 出的
    /// 激活 / 焦点 / 松键事件都可能让前台 app 的 hover 提前消失。冻结期间阻塞主线程
    /// 反而是特性：focus 事件没机会插队。
    ///
    /// 冻结帧来源（按优先级）：
    ///  1. **预冻结抢跑帧**——修饰键按满那一刻抓的，早于 A 键 keyDown 与所有松键事件；
    ///  2. **现场并行补抓**——只补预冻结缺失 / 过期 / 失败的显示器，并行发起、有界等待。
    @MainActor
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

        var frozen: [CGDirectDisplayID: ParallelDisplayFreezer.FrozenFrame] = [:]

        // 1) 消费新鲜的预冻结帧。抢跑通常在几十毫秒前就已发起，wait 大多立即返回；
        //    若用户按 A 极快、抓取仍在途，这里最多再等 250ms 收尾。
        if let pre = takeFreshPreFreeze(maxAgeMilliseconds: 400) {
            let frames = pre.wait(timeout: .milliseconds(250))
            for (id, frame) in frames { frozen[id] = frame }
            NSLog("[CaptureManager] 使用预冻结帧：\(frames.count) 屏，age≈\(Int(pre.ageMilliseconds))ms")
        }

        // 2) 缺口的显示器现场并行补抓（无预冻结权限 / 预冻结过期 / 单屏失败都落在这里）。
        let missing = targets.compactMap { target -> ParallelDisplayFreezer.Request? in
            guard let id = target.displayID, frozen[id] == nil else { return nil }
            return ParallelDisplayFreezer.Request(displayID: id, frameSize: target.frameSize)
        }
        if !missing.isEmpty {
            let freezer = ParallelDisplayFreezer(requests: missing)
            let frames = freezer.wait(timeout: .milliseconds(300))
            for (id, frame) in frames { frozen[id] = frame }
            if frames.count < missing.count {
                NSLog("[CaptureManager] 现场补抓不完整：\(frames.count)/\(missing.count) 屏，缺的屏将走 SCK live 兜底")
            }
        }

        presentCaptureOverlays(targets.map { target in
            (target: target, frozen: target.displayID.flatMap { frozen[$0] })
        })
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
    private func presentCaptureOverlays(
        _ prepared: [(target: CaptureTarget, frozen: ParallelDisplayFreezer.FrozenFrame?)]
    ) {
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

                // 排除自身所有窗口——按 application 而非按窗口列表：
                // overlay 上屏后窗口列表可能变化，按 app 排除更稳
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
