// AppDelegate.swift
// 应用代理，负责初始化各核心模块并协调通知

import AppKit
import CoreGraphics

class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - 核心模块

    private var statusBarController: StatusBarController!
    private var welcomeWindowController: WelcomeWindowController?

    /// 防止 reopen 循环触发
    private var isHandlingReopen = false

    // MARK: - 生命周期

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController()
        _ = HotkeyManager.shared
        _ = CaptureManager.shared
        _ = RecordingManager.shared
        setupNotificationObservers()

        if !UserDefaults.standard.bool(forKey: UDKey.hasCompletedOnboarding) {
            showWelcomeWindow()
        } else {
            SettingsWindowController.shared.showWindow()
        }

        // 启动 3s 后台后台检查更新（24h 防抖在 UpdateChecker 内部处理）
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            UpdateChecker.shared.checkOnLaunchIfNeeded()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !isHandlingReopen else { return false }
        isHandlingReopen = true
        SettingsWindowController.shared.showWindow()
        DispatchQueue.main.async { self.isHandlingReopen = false }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.unregisterHotkey()
    }

    // MARK: - 欢迎引导

    private func showWelcomeWindow() {
        let controller = WelcomeWindowController { [weak self] in
            self?.welcomeWindowController = nil
        }
        controller.showWindow()
        welcomeWindowController = controller
    }

    // MARK: - 通知监听

    private func setupNotificationObservers() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(handleStartCapture(_:)),
                           name: .captureRequested, object: nil)
        center.addObserver(self, selector: #selector(handleStartRecording(_:)),
                           name: .recordingRequested, object: nil)
    }

    @objc private func handleStartCapture(_ notification: Notification) {
        // 录屏进行时不允许触发截图——保护正在写盘的视频会话。
        // 用户按了全局热键以为没反应，所以这里弹一条 toast 明确告知（菜单条已 disabled，
        // 但热键路径没有视觉反馈）。
        if RecordingManager.shared.isActive {
            NSLog("[AppDelegate] 截图请求被忽略：录屏正在进行")
            CopyToast.show(image: Self.busyPlaceholderImage(),
                           message: "录屏进行中，无法截图",
                           subtitle: "停止当前录屏后再试")
            return
        }
        guard ensureScreenCapturePermission() else { return }
        CaptureManager.shared.startCapture()
    }

    /// 录屏热键 / 菜单的 toggle 语义在这里翻译：
    ///   .idle          → 权限校验 + 进入取景
    ///   .pickingRegion → 取消取景（等价于 Esc）
    ///   .recording     → 停止录制并写盘
    /// 控制面板的"停止"按钮、Esc 等其它停止入口走 `.recordingStopRequested`（RecordingManager 自己订阅）。
    @objc private func handleStartRecording(_ notification: Notification) {
        let rec = RecordingManager.shared
        switch rec.state {
        case .recording, .pickingRegion:
            NotificationCenter.default.post(name: .recordingStopRequested, object: nil)
            return
        case .idle:
            break
        }
        if CaptureManager.shared.isCapturing {
            NSLog("[AppDelegate] 录屏请求被忽略：截图正在进行")
            CopyToast.show(image: Self.busyPlaceholderImage(),
                           message: "截图进行中，无法录屏",
                           subtitle: "完成或取消当前截图后再试")
            return
        }
        guard ensureScreenCapturePermission() else { return }
        rec.startPickingRegion()
    }

    /// 占位缩略图：截图/录屏互拒 toast 时用，避免 toast 显示空白图框。
    private static func busyPlaceholderImage() -> NSImage {
        let cfg = NSImage.SymbolConfiguration(pointSize: 28, weight: .semibold)
        if let sym = NSImage(systemSymbolName: "exclamationmark.octagon.fill",
                             accessibilityDescription: "无法操作")?
            .withSymbolConfiguration(cfg) {
            return sym
        }
        return NSImage(size: NSSize(width: 32, height: 32))
    }

    /// 弹"拖拽授权"气泡引导用户去系统设置；返回 true 代表权限已具备，调用方可继续。
    ///
    /// 早先版本是 NSAlert + 老 URL，但用户经常卡在"系统设置里找不到 Snap²"——TCC 没注册
    /// 时 .app 根本不出现在权限列表里。现在改成贴在系统设置下方的拖拽气泡：用户把图标
    /// 拖进列表就完成授权，等同于从 Finder 拖 .app。
    ///
    /// 授权成功后只 dismiss 气泡 + 弹 toast 提示，不做 auto-retry：跨秒级异步重试容易
    /// 变成"幽灵截图"，让用户手动再触发一次更稳。
    private func ensureScreenCapturePermission() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        PermissionAssistant.shared.present(
            panel: .screenRecording,
            from: nil,
            onGranted: {
                CopyToast.show(
                    image: Self.busyPlaceholderImage(),
                    message: "已授权 Snap²",
                    subtitle: "再次按快捷键即可截图 / 录屏"
                )
            },
            onCancel: nil
        )
        return false
    }

}
