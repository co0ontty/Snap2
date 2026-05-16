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
        // 录屏进行时不允许触发截图——保护正在写盘的视频会话
        if RecordingManager.shared.isActive {
            NSLog("[AppDelegate] 截图请求被忽略：录屏正在进行")
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
            return
        }
        guard ensureScreenCapturePermission() else { return }
        rec.startPickingRegion()
    }

    /// 弹窗 + 跳转系统设置；返回 true 代表权限已具备，调用方可继续
    private func ensureScreenCapturePermission() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        let alert = NSAlert()
        alert.messageText = "需要屏幕录制权限"
        alert.informativeText = "请在「系统设置 → 隐私与安全性 → 屏幕录制」中为 Snap² 开启权限，然后重试。"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "取消")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
        return false
    }

}
