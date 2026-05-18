// StatusBarController.swift
// 管理菜单栏状态栏图标和下拉菜单

import AppKit

class StatusBarController {

    // MARK: - 属性

    private var statusItem: NSStatusItem
    private var captureItem: NSMenuItem!
    private var recordItem: NSMenuItem!
    private var updateItem: NSMenuItem!

    /// 录制中追加在菜单栏的"时长 label"。停止按钮已不再放在状态栏：
    /// 状态栏永远在系统主菜单栏所在屏，主屏与录屏屏不同时停止按钮会"跨屏"，
    /// 而 RecordingControlPanel 已经把停止按钮放在录屏所在屏右上角。
    private var recordingTimerItem: NSStatusItem?
    private var recordingTimer: Timer?
    private var recordingStartedAt: Date?

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
        // 设置窗口等外部入口可通过通知请求一次更新检查，复用同一套 alert/install 流程
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleUpdateCheckRequested(_:)),
            name: .updateCheckRequested,
            object: nil
        )
        // 录制开始 / 结束 → 切换菜单栏图标 + 插拔"快捷操作"按钮
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRecordingStarted(_:)),
            name: .recordingStarted,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRecordingFinished(_:)),
            name: .recordingFinished,
            object: nil
        )
    }

    deinit {
        recordingTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - 配置

    private func setupButton() {
        applyIdleAppearance()
    }

    /// 闲置态：cat.fill 图标 + 默认 tint
    private func applyIdleAppearance() {
        guard let button = statusItem.button else { return }
        let symbol = NSImage(systemSymbolName: "cat.fill", accessibilityDescription: "Snap² 截图")
            ?? NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Snap² 截图")
        if let image = symbol {
            image.isTemplate = true
            button.image = image
        }
        button.contentTintColor = nil
        button.toolTip = "Snap² · 截图工具"
    }

    /// 录制态：record.circle.fill 红色，配合呼吸感（菜单栏不支持图层动画，这里只换图标即可）
    private func applyRecordingAppearance() {
        guard let button = statusItem.button else { return }
        let symbol = NSImage(systemSymbolName: "record.circle.fill",
                             accessibilityDescription: "Snap² 正在录屏")
        if let image = symbol {
            image.isTemplate = true
            button.image = image
        }
        button.contentTintColor = .systemRed
        button.toolTip = "Snap² · 正在录屏（点击展开）"
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

        // 区域录屏
        let recordHotkeyDisplay = KeyCodeMapping.displayString(
            keyCode: manager.keyCode(for: .record),
            carbonModifiers: manager.modifiers(for: .record)
        )
        recordItem = NSMenuItem(
            title: "区域录屏    \(recordHotkeyDisplay)",
            action: #selector(recordRegion),
            keyEquivalent: ""
        )
        recordItem.target = self
        recordItem.image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: nil)
        menu.addItem(recordItem)

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

    @objc private func recordRegion() {
        // 同截图：走 AppDelegate 的权限检查
        NotificationCenter.default.post(name: .recordingRequested, object: nil)
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

        let recordDisplay = KeyCodeMapping.displayString(
            keyCode: manager.keyCode(for: .record),
            carbonModifiers: manager.modifiers(for: .record)
        )
        recordItem?.title = "区域录屏    \(recordDisplay)"
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

    @objc private func handleUpdateCheckRequested(_ note: Notification) {
        checkForUpdate()
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

    // MARK: - 录制中的菜单栏快捷操作

    @objc private func handleRecordingStarted(_ note: Notification) {
        applyRecordingAppearance()
        installRecordingQuickActions()
        updateMenuForRecording(true)
    }

    @objc private func handleRecordingFinished(_ note: Notification) {
        applyIdleAppearance()
        removeRecordingQuickActions()
        updateMenuForRecording(false)
    }

    /// 在主图标右侧追加一个 NSStatusItem：时长 label。
    /// 停止入口由 RecordingControlPanel（位于录屏所在屏）与全局热键 / Esc 共同承担。
    private func installRecordingQuickActions() {
        removeRecordingQuickActions()  // 防御性：重入时先清掉

        // 时长 label（variableLength：宽度跟随 title）
        let timer = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = timer.button {
            btn.title = "00:00"
            btn.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            btn.contentTintColor = .systemRed
            btn.toolTip = "Snap² · 录制时长"
        }
        recordingTimerItem = timer

        // 启动 1Hz 计时器更新时长
        recordingStartedAt = Date()
        recordingTimer?.invalidate()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tickRecordingTimer()
        }
        RunLoop.main.add(t, forMode: .common)
        recordingTimer = t
        tickRecordingTimer()  // 立即刷一次到 00:00
    }

    private func removeRecordingQuickActions() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingStartedAt = nil
        if let item = recordingTimerItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        recordingTimerItem = nil
    }

    private func tickRecordingTimer() {
        guard let start = recordingStartedAt else { return }
        let elapsed = Int(Date().timeIntervalSince(start))
        let h = elapsed / 3600
        let m = (elapsed % 3600) / 60
        let s = elapsed % 60
        let text = h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
        recordingTimerItem?.button?.title = text
        // 录制中也更新 record 菜单条目里的时长（如果当前是 "停止录屏" 状态）
        if recordItem?.title.hasPrefix("停止录屏") == true {
            recordItem.title = "停止录屏 \(text)"
        }
    }

    /// 录制中：截图条目禁用、录制条目变 "停止录屏"。
    /// 结束：复原默认显示（带快捷键 hint）。
    private func updateMenuForRecording(_ recording: Bool) {
        if recording {
            captureItem?.isEnabled = false
            captureItem?.title = "区域截图（录屏进行中）"
            recordItem?.image = NSImage(systemSymbolName: "stop.circle.fill",
                                        accessibilityDescription: nil)
            recordItem?.title = "停止录屏 00:00"
        } else {
            captureItem?.isEnabled = true
            recordItem?.image = NSImage(systemSymbolName: "record.circle",
                                        accessibilityDescription: nil)
            // 复原显示（带最新的快捷键文案）
            updateCaptureShortcutDisplay()
        }
    }
}
