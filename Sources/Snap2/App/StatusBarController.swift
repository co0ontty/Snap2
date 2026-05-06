// StatusBarController.swift
// 管理菜单栏状态栏图标和下拉菜单

import AppKit

class StatusBarController {

    // MARK: - 属性

    private var statusItem: NSStatusItem
    private var captureItem: NSMenuItem!
    private var updateItem: NSMenuItem!

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
        case .newer(let current, let latest, let url):
            alert.messageText = "发现新版本 v\(latest)"
            alert.informativeText = "你正在使用 v\(current)。要查看更新内容吗？"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "查看 Release")
            alert.addButton(withTitle: "稍后")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(url)
            }
        case .error(let msg):
            alert.messageText = "检查更新失败"
            alert.informativeText = msg
            alert.alertStyle = .warning
            alert.addButton(withTitle: "好")
            alert.runModal()
        }
    }

    @objc private func handleUpdateAvailable(_ note: Notification) {
        guard let outcome = note.object as? UpdateChecker.Outcome,
              case .newer(_, let latest, _) = outcome else { return }
        applyUpdateAvailable(latestVersion: latest)
    }

    private func applyUpdateAvailable(latestVersion: String) {
        updateItem?.title = "新版本 v\(latestVersion) 可用..."
        updateItem?.image = NSImage(systemSymbolName: "arrow.down.circle.fill",
                                    accessibilityDescription: nil)
        statusItem.button?.toolTip = "Snap² · 新版本 v\(latestVersion) 可用"
    }
}
