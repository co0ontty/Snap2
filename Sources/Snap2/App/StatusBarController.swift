// StatusBarController.swift
// 管理菜单栏状态栏图标和下拉菜单

import AppKit

class StatusBarController {

    // MARK: - 属性

    private var statusItem: NSStatusItem
    private var captureItem: NSMenuItem!

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
}
