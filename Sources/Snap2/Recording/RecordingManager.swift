import AppKit
import AVFoundation
import CoreMedia
import ScreenCaptureKit

/// 区域录屏单例。状态机：
///   .idle → .pickingRegion → .recording → .idle
///
/// 与 `CaptureManager` 互斥。AppDelegate 在收到 `.recordingRequested` 后调用
/// `startPickingRegion()`；用户点 "开始" 后切到 `.recording`，启动 SCStream + AVAssetWriter；
/// 点停止或再次按热键则结束并写盘。
final class RecordingManager: NSObject {

    // MARK: - 单例
    static let shared = RecordingManager()

    // MARK: - 状态
    enum State: Equatable {
        case idle
        case pickingRegion
        case recording
    }
    private(set) var state: State = .idle

    /// 给 CaptureManager 互锁用的便利标志
    var isActive: Bool { state != .idle }

    // MARK: - 取景态
    private var overlayWindows: [OverlayWindow] = []

    // MARK: - 录制态
    private var stream: SCStream?
    private var writer: RecordingVideoWriter?
    private var controlPanel: RecordingControlPanel?
    /// 录制专用 SCStream 输出回调队列：video 与 audio 各一条，避免互相阻塞
    private let videoOutputQueue = DispatchQueue(label: "com.chuer.snap2.recording.video",
                                                  qos: .userInitiated)
    private let audioOutputQueue = DispatchQueue(label: "com.chuer.snap2.recording.audio",
                                                  qos: .userInitiated)

    // MARK: - Notification 订阅
    private var stopObserver: NSObjectProtocol?

    private override init() {
        super.init()
        // 录屏热键二次触发 / 控制面板按钮 / Esc 确认 → 统一走 `.recordingStopRequested`
        stopObserver = NotificationCenter.default.addObserver(
            forName: .recordingStopRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleStopRequest()
        }
    }

    deinit {
        if let obs = stopObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    // MARK: - 入口

    /// 由 AppDelegate 在权限 OK 后调用
    func startPickingRegion() {
        guard state == .idle else { return }
        guard !CaptureManager.shared.isCapturing else {
            // 截图正在进行——拒绝重入。简单地不做事（截图自身有 toast/反馈）
            return
        }

        state = .pickingRegion
        NSCursor.crosshair.push()

        for screen in NSScreen.screens {
            let overlay = OverlayWindow(screen: screen)
            // 替换 contentView 为录屏取景视图
            let picker = RecordingSelectionView(frame: overlay.contentRect(forFrameRect: overlay.frame))
            picker.targetScreen = screen
            picker.delegate = self
            overlay.contentView = picker
            _ = overlay.makeFirstResponder(picker)
            overlay.makeKeyAndOrderFront(nil)
            overlayWindows.append(overlay)
        }
        NSApp.activate(ignoringOtherApps: true)
        overlayWindows.first?.makeKey()
    }

    /// 跳过取景阶段，直接以外部已确定的选区开始录屏。
    /// 用于"截图框选后切到录屏"的快捷路径——调用方需保证：
    ///   - 自己已经把任何持有屏幕的截图 overlay 关闭（避免被录进 SCStream）
    ///   - rect 是 *overlay 视图坐标* / `screen` 是 rect 所在屏（与 RecordingSelectionView 同义）
    func startRecordingForRegion(_ rect: NSRect, on screen: NSScreen) {
        guard state == .idle else { return }
        guard !CaptureManager.shared.isCapturing else {
            NSLog("[RecordingManager] startRecordingForRegion 被忽略：CaptureManager 仍在截图")
            return
        }
        // beginRecording 期望 state == .pickingRegion 才会真正启动；
        // 这里手动满足前置条件，复用相同的"取景确认 → 启动 SCStream"路径。
        state = .pickingRegion
        beginRecording(selectionInView: rect, screen: screen)
    }

    private func closeAllOverlays() {
        NSCursor.pop()
        for w in overlayWindows {
            (w.contentView as? RecordingSelectionView)?.prepareForClose()
            w.contentView = nil
            w.orderOut(nil)
        }
        overlayWindows.removeAll()
    }

    // MARK: - 启动录制（取景确认后）

    private func beginRecording(selectionInView rect: NSRect, screen: NSScreen) {
        guard state == .pickingRegion else { return }

        // 选区视图坐标 → 屏幕坐标（与 CaptureManager.captureInline 同源换算逻辑）
        let mainScreenHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let screenOriginX = screen.frame.origin.x + rect.origin.x
        let screenOriginY = screen.frame.origin.y + rect.origin.y
        let sourceRect = CGRect(
            x: screenOriginX,
            y: mainScreenHeight - screenOriginY - rect.height,
            width: rect.width,
            height: rect.height
        )

        let backingScale = screen.backingScaleFactor
        let pixelW = Int(round(rect.width * backingScale))
        let pixelH = Int(round(rect.height * backingScale))
        guard pixelW > 0, pixelH > 0 else {
            cancelPickingDueToInvalidRegion()
            return
        }

        // overlay 关闭要早于 SCStream 启动——否则 SCStream 会把我们的暗色 overlay
        // 也录进去（即使 contentFilter 已经把窗口排掉了，避免任何竞态）
        closeAllOverlays()

        let outputURL = computeOutputURL()
        let includesAudio = UserDefaults.standard.object(forKey: UDKey.recordingCapturesSystemAudio) as? Bool ?? true

        let writer: RecordingVideoWriter
        do {
            writer = try RecordingVideoWriter(outputURL: outputURL,
                                               pixelWidth: pixelW,
                                               pixelHeight: pixelH,
                                               includesAudio: includesAudio)
            try writer.startWriting()
        } catch {
            state = .idle
            showFailureToast(message: "录屏初始化失败", error: error)
            return
        }
        self.writer = writer

        // 准备 SCStream
        let screenDisplayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID

        Task { @MainActor in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                // 取消检查 #1：用户在 await 期间按了 ⌃⇧R 或 Esc，state 已经被翻成 .idle。
                // 此时不再继续启动 SCStream，把刚建的 writer 清理掉。
                guard self.state == .pickingRegion else {
                    self.writer?.cancel()
                    self.writer = nil
                    return
                }
                guard let display = content.displays.first(where: { $0.displayID == screenDisplayID })
                        ?? content.displays.first else {
                    throw NSError(domain: "RecordingManager",
                                  code: -10,
                                  userInfo: [NSLocalizedDescriptionKey: "找不到匹配的 SCDisplay"])
                }
                // 排除 Snap2 自身整个进程的窗口——这条比 `excludingWindows:` 关键：
                // 控制面板 / toast 都是在 stream 起来 *之后* 才创建，按窗口列表过滤就漏了；
                // 按 application 排除则任何当前 / 未来 Snap2 窗口都不会被录进视频。
                let selfBundleID = AppInfo.currentBundleID
                let excludeApps = content.applications.filter {
                    $0.bundleIdentifier == selfBundleID
                }
                let filter = SCContentFilter(display: display,
                                              excludingApplications: excludeApps,
                                              exceptingWindows: [])

                let config = SCStreamConfiguration()
                config.sourceRect = sourceRect
                config.width = pixelW
                config.height = pixelH
                config.scalesToFit = false
                config.showsCursor = true  // 录屏一般要看到鼠标——后续可做开关
                config.pixelFormat = kCVPixelFormatType_32BGRA
                config.colorSpaceName = CGColorSpace.displayP3
                // 30fps 上限——minimumFrameInterval 是最小帧间隔，等价于上限 fps
                config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
                config.queueDepth = 6
                if includesAudio {
                    config.capturesAudio = true
                    config.excludesCurrentProcessAudio = true  // 防自循环（toast 提示音等）
                }

                let stream = SCStream(filter: filter, configuration: config, delegate: self)
                try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: self.videoOutputQueue)
                if includesAudio {
                    try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: self.audioOutputQueue)
                }

                try await stream.startCapture()
                // 取消检查 #2：startCapture 自身是 async；用户可能在这一段把状态改了。
                // 此时 SCStream 已经在跑，必须显式 stop + 清理。
                guard self.state == .pickingRegion else {
                    try? await stream.stopCapture()
                    self.writer?.cancel()
                    self.writer = nil
                    return
                }
                self.stream = stream
                self.state = .recording
                // NSScreen 非 Sendable，不能在 @Sendable Task 闭包里直接捕获外层引用；
                // 改用前面提出来的 displayID 在 main actor 上反查，等价但 Sendable 干净。
                let panelScreen = NSScreen.screens.first(where: {
                    ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == screenDisplayID
                }) ?? NSScreen.main
                if let panelScreen {
                    self.showControlPanel(on: panelScreen)
                }
                NotificationCenter.default.post(name: .recordingStarted, object: nil)
            } catch {
                self.writer?.cancel()
                self.writer = nil
                self.state = .idle
                self.showFailureToast(message: "录屏启动失败", error: error)
            }
        }
    }

    private func cancelPickingDueToInvalidRegion() {
        closeAllOverlays()
        state = .idle
    }

    // MARK: - 停止 / 取消

    private func handleStopRequest() {
        switch state {
        case .recording:
            stopRecording()
        case .pickingRegion:
            // 录屏热键在取景阶段再按一次 = 取消
            closeAllOverlays()
            state = .idle
        case .idle:
            break
        }
    }

    /// 用户主动停止：SCStream 停 → writer.finish → toast + post notification
    private func stopRecording() {
        guard state == .recording else { return }
        // 立刻把状态置为 idle，避免热键 / 停止按钮重复触发
        state = .idle

        controlPanel?.dismiss { [weak self] in
            self?.controlPanel = nil
        }

        let writer = self.writer
        self.writer = nil

        if let stream = self.stream {
            self.stream = nil
            stream.stopCapture { _ in
                // SCStream 已停；剩余在途 buffer 会被丢弃，writer.finish 完成残余写入
                DispatchQueue.main.async {
                    self.finishWriter(writer)
                }
            }
        } else {
            finishWriter(writer)
        }
    }

    private func finishWriter(_ writer: RecordingVideoWriter?) {
        guard let writer = writer else {
            NotificationCenter.default.post(name: .recordingFinished, object: nil)
            return
        }
        writer.finish { [weak self] result in
            switch result {
            case .success(let url):
                self?.showSuccessToast(fileURL: url)
            case .failure(let err):
                self?.showFailureToast(message: "录屏保存失败", error: err)
            }
            NotificationCenter.default.post(name: .recordingFinished, object: nil)
        }
    }

    // MARK: - Toast

    private func showSuccessToast(fileURL: URL) {
        let placeholder = recordingThumbnail()
        CopyToast.show(image: placeholder,
                       message: "录屏已保存",
                       subtitle: fileURL.lastPathComponent)
    }

    private func showFailureToast(message: String, error: Error) {
        NSLog("[RecordingManager] \(message): \(error)")
        let placeholder = recordingThumbnail()
        CopyToast.show(image: placeholder,
                       message: message,
                       subtitle: (error as NSError).localizedDescription)
    }

    /// CopyToast 需要一个 NSImage 缩略图——录屏没有静态首帧，用 SF Symbol 占位
    private func recordingThumbnail() -> NSImage {
        let cfg = NSImage.SymbolConfiguration(pointSize: 36, weight: .semibold)
        let sym = NSImage(systemSymbolName: "record.circle.fill",
                          accessibilityDescription: "录屏")?
            .withSymbolConfiguration(cfg)
        let img = sym ?? NSImage(size: NSSize(width: 48, height: 48))
        return img
    }

    // MARK: - 控制面板

    private func showControlPanel(on screen: NSScreen) {
        let panel = RecordingControlPanel()
        panel.onStop = {
            // 走统一的 stopRequested 流，让热键和按钮共享一条路径
            NotificationCenter.default.post(name: .recordingStopRequested, object: nil)
        }
        panel.showAndStart(on: screen)
        controlPanel = panel
    }

    // MARK: - 输出目录 / 文件名

    private func computeOutputURL() -> URL {
        OutputFileHelper.recordingURL()
    }
}

// MARK: - RecordingSelectionViewDelegate

extension RecordingManager: RecordingSelectionViewDelegate {
    func recordingSelectionDidConfirm(_ view: RecordingSelectionView,
                                      selectionInView rect: NSRect,
                                      screen: NSScreen) {
        beginRecording(selectionInView: rect, screen: screen)
    }

    func recordingSelectionDidCancel(_ view: RecordingSelectionView) {
        closeAllOverlays()
        state = .idle
    }
}

// MARK: - SCStreamDelegate

extension RecordingManager: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("[RecordingManager] SCStream didStopWithError: \(error)")
        DispatchQueue.main.async { [weak self] in
            // SCK 自身停了——按"用户期望的停止"处理：finalize writer + toast 失败
            guard let self = self else { return }
            guard self.state == .recording else { return }
            self.state = .idle
            self.controlPanel?.dismiss { [weak self] in self?.controlPanel = nil }
            self.stream = nil
            let writer = self.writer
            self.writer = nil
            writer?.finish { res in
                switch res {
                case .success(let url):
                    self.showSuccessToast(fileURL: url)
                case .failure:
                    self.showFailureToast(message: "录屏意外中止", error: error)
                }
                NotificationCenter.default.post(name: .recordingFinished, object: nil)
            }
        }
    }
}

// MARK: - SCStreamOutput

extension RecordingManager: SCStreamOutput {
    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        // 注意：本回调在 video/audio 各自的 sample handler queue 上，不是主线程
        switch type {
        case .screen:
            // SCStream 用 SCFrameStatus 标 attachments；只接受 .complete 帧
            if let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
               let info = attachmentsArray.first,
               let raw = info[SCStreamFrameInfo.status] as? Int,
               let status = SCFrameStatus(rawValue: raw),
               status != .complete {
                return
            }
            writer?.append(videoBuffer: sampleBuffer)
        case .audio:
            writer?.append(audioBuffer: sampleBuffer)
        case .microphone:
            break
        @unknown default:
            break
        }
    }
}
