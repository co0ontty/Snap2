// StatusBarController.swift
// 管理菜单栏状态栏图标和下拉菜单

import AppKit

class StatusBarController {

    // MARK: - 属性

    private var statusItem: NSStatusItem
    private var captureItem: NSMenuItem!
    private var updateItem: NSMenuItem!

    /// 自动更新进度窗口，避免被 ARC 提前回收
    private var updateProgressWindow: UpdateProgressWindow?

    private var settingsWindowController: SettingsWindowController { SettingsWindowController.shared }

    // MARK: - 初始化

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        setupButton()
        setupMenu()

        // 监听快捷键变更通知，更新菜单显示
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateCaptureShortcutDisplay),
            name: .hotkeyChanged,
            object: nil
        )
        // 监听更新可用通知，刷新菜单条目
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleUpdateAvailable(_:)),
            name: .updateAvailable,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - 配置

    private func setupButton() {
        guard let button = statusItem.button else { return }

        // 优先用 cat.fill（macOS 14+ SF Symbol，呼应"初二"），不可用时回退到 camera.viewfinder
        let symbol = NSImage(systemSymbolName: "cat.fill", accessibilityDescription: "Snap² 截图")
            ?? NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Snap² 截图")
        if let image = symbol {
            image.isTemplate = true
            button.image = image
        }

        button.toolTip = "Snap² · 截图工具"
    }

    private func setupMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        // 区域截图（显示当前快捷键）
        let manager = HotkeyManager.shared
        let hotkeyDisplay = KeyCodeMapping.displayString(
            keyCode: manager.currentKeyCode,
            carbonModifiers: manager.currentModifiers
        )

        captureItem = NSMenuItem(
            title: "区域截图    \(hotkeyDisplay)",
            action: #selector(captureRegion),
            keyEquivalent: ""
        )
        captureItem.target = self
        captureItem.image = NSImage(systemSymbolName: "crop", accessibilityDescription: nil)
        menu.addItem(captureItem)

        menu.addItem(NSMenuItem.separator())

        // 设置
        let settingsItem = NSMenuItem(
            title: "设置...",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(settingsItem)

        // 检查更新
        updateItem = NSMenuItem(
            title: "检查更新...",
            action: #selector(checkForUpdate),
            keyEquivalent: ""
        )
        updateItem.target = self
        updateItem.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil)
        menu.addItem(updateItem)

        // 上次启动检查已发现新版本：直接以"新版本可用"形态出现（语义版本比较）
        if let latest = UserDefaults.standard.string(forKey: UDKey.lastKnownLatestVersion),
           !latest.isEmpty,
           UpdateChecker.isVersionNewer(latest, than: UpdateChecker.shared.currentVersion)
        {
            applyUpdateAvailable(latestVersion: latest)
        }

        // 关于
        let aboutItem = NSMenuItem(
            title: "关于 Snap²",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        aboutItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        // 退出
        let quitItem = NSMenuItem(
            title: "退出 Snap²",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - 菜单动作

    @objc private func captureRegion() {
        // 通过通知触发，走 AppDelegate 的权限检查
        NotificationCenter.default.post(name: .captureRequested, object: nil)
    }

    @objc private func openSettings() {
        settingsWindowController.showWindow()
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - 更新快捷键显示

    @objc private func updateCaptureShortcutDisplay() {
        let manager = HotkeyManager.shared
        let hotkeyDisplay = KeyCodeMapping.displayString(
            keyCode: manager.currentKeyCode,
            carbonModifiers: manager.currentModifiers
        )
        captureItem?.title = "区域截图    \(hotkeyDisplay)"
    }

    // MARK: - 更新检查

    @objc private func checkForUpdate() {
        UpdateChecker.shared.checkManually { [weak self] outcome in
            self?.presentCheckResult(outcome)
        }
    }

    private func presentCheckResult(_ outcome: UpdateChecker.Outcome) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        switch outcome {
        case .upToDate(let current):
            alert.messageText = "已是最新版本"
            alert.informativeText = "当前 v\(current) 已是最新。"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "好")
            alert.runModal()
        case .newer(let current, let latest, let url, let assets):
            presentNewerAlert(current: current, latest: latest, releaseURL: url, assets: assets)
            return
        case .error(let msg):
            alert.messageText = "检查更新失败"
            alert.informativeText = msg
            alert.alertStyle = .warning
            alert.addButton(withTitle: "好")
            alert.runModal()
        }
    }

    /// 新版本弹窗。能自动下载 + 当前 .app 路径可写时，提供「立即更新」按钮；
    /// 否则只能跳转 Release 页面手动下载。
    private func presentNewerAlert(current: String,
                                   latest: String,
                                   releaseURL: URL,
                                   assets: UpdateChecker.ReleaseAssets) {
        let alert = NSAlert()
        alert.messageText = "发现新版本 v\(latest)"
        alert.alertStyle = .informational

        let canAutoUpdate = assets.preferredDownload != nil && UpdateInstaller.canInstallInPlace
        if canAutoUpdate {
            alert.informativeText = """
            当前版本 v\(current)。

            点击「立即更新」自动下载并替换。

            注意：当前版本未使用 Apple Developer ID 签名，更新后系统会要求重新授予「屏幕录制」权限（系统设置 > 隐私与安全性 > 屏幕录制）。
            """
            alert.addButton(withTitle: "立即更新")
            alert.addButton(withTitle: "查看 Release")
            alert.addButton(withTitle: "稍后")
        } else {
            let reason: String
            if assets.preferredDownload == nil {
                reason = "Release 没有上传可下载的产物（zip/dmg），请到 GitHub 手动下载。"
            } else {
                reason = "当前 app 所在目录不可写（\(Bundle.main.bundlePath)），请先把 app 拖到 Applications 文件夹后再使用自动更新。"
            }
            alert.informativeText = "当前版本 v\(current)。\n\n\(reason)"
            alert.addButton(withTitle: "查看 Release")
            alert.addButton(withTitle: "稍后")
        }

        let response = alert.runModal()
        if canAutoUpdate {
            switch response {
            case .alertFirstButtonReturn:
                startAutoUpdate(assets: assets, releaseURL: releaseURL)
            case .alertSecondButtonReturn:
                NSWorkspace.shared.open(releaseURL)
            default:
                break
            }
        } else if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(releaseURL)
        }
    }

    private func startAutoUpdate(assets: UpdateChecker.ReleaseAssets, releaseURL: URL) {
        let win = UpdateProgressWindow()
        win.onCancel = { [weak self] in
            UpdateInstaller.shared.cancel()
            self?.updateProgressWindow = nil
        }
        updateProgressWindow = win
        win.showCentered()

        UpdateInstaller.shared.startUpdate(assets: assets) { [weak self] stage in
            self?.handleInstallerStage(stage, releaseURL: releaseURL)
        }
    }

    private func handleInstallerStage(_ stage: UpdateInstaller.Stage, releaseURL: URL) {
        switch stage {
        case .downloading(let received, let total):
            updateProgressWindow?.setDownloading(received: received, total: total)
        case .extracting:
            updateProgressWindow?.setExtracting()
        case .readyToRelaunch(let stagedAppPath):
            updateProgressWindow?.close()
            updateProgressWindow = nil
            confirmRelaunch(stagedAppPath: stagedAppPath, releaseURL: releaseURL)
        case .failed(let msg):
            updateProgressWindow?.close()
            updateProgressWindow = nil
            showAutoUpdateFailure(msg, releaseURL: releaseURL)
        }
    }

    private func confirmRelaunch(stagedAppPath: String, releaseURL: URL) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "新版本已下载完成"
        alert.informativeText = "立即重启更新到新版本？"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "立即重启")
        alert.addButton(withTitle: "稍后手动启动")
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            // 把 staged app 路径告知用户，让他自己手动接管
            let info = NSAlert()
            info.messageText = "新版本已下载到："
            info.informativeText = stagedAppPath
            info.addButton(withTitle: "好")
            info.runModal()
            return
        }
        switch UpdateInstaller.shared.relaunch(stagedAppPath: stagedAppPath) {
        case .success:
            NSApp.terminate(nil)
        case .failure(let err):
            showAutoUpdateFailure("重启更新失败: \(err.localizedDescription)\n\n新版本已下载到：\(stagedAppPath)",
                                  releaseURL: releaseURL)
        }
    }

    private func showAutoUpdateFailure(_ message: String, releaseURL: URL) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "自动更新失败"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "查看 Release")
        alert.addButton(withTitle: "关闭")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(releaseURL)
        }
    }

    @objc private func handleUpdateAvailable(_ note: Notification) {
        guard let outcome = note.object as? UpdateChecker.Outcome,
              case .newer(_, let latest, _, _) = outcome else { return }
        applyUpdateAvailable(latestVersion: latest)
    }

    private func applyUpdateAvailable(latestVersion: String) {
        updateItem?.title = "新版本 v\(latestVersion) 可用..."
        updateItem?.image = NSImage(systemSymbolName: "arrow.down.circle.fill",
                                    accessibilityDescription: nil)
        statusItem.button?.toolTip = "Snap² · 新版本 v\(latestVersion) 可用"
    }
}
