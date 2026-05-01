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
        setupNotificationObservers()

        if !UserDefaults.standard.bool(forKey: UDKey.hasCompletedOnboarding) {
            showWelcomeWindow()
        } else {
            SettingsWindowController.shared.showWindow()
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
    }

    @objc private func handleStartCapture(_ notification: Notification) {
        if !CGPreflightScreenCaptureAccess() {
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
            return
        }
        CaptureManager.shared.startCapture()
    }

}
