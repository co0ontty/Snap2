import AppKit
import CoreGraphics
import Foundation

/// Codex 风格"拖拽授权"气泡的对外入口。
///
/// 调用 `present(panel:from:onGranted:onCancel:)` 后：
/// 1. 打开系统设置对应面板。
/// 2. 在系统设置窗口下方弹一个悬浮气泡（GlassPanel 暗色玻璃），里面是可拖拽的应用图标。
/// 3. 内部跑一个 150ms 的 timer 同时做两件事：
///    - 跟踪系统设置窗口位置变化，刷新气泡 origin；
///    - 每 ~450ms (3 tick) 调一次 `CGPreflightScreenCaptureAccess()` 检测授权状态。
/// 4. 检测到已授权 → dismiss 气泡 + 调 `onGranted`。用户点 ← 返回 → dismiss + `onCancel`。
///
/// 单例保证同时最多只有一个气泡，避免重复 present 时多窗口堆叠。
@MainActor
final class PermissionAssistant {

    static let shared = PermissionAssistant()

    private var overlay: PermissionOverlayController?
    private var trackingTimer: Timer?
    private var activationObserver: NSObjectProtocol?

    private var activePanel: PermissionPanel?
    private var pendingSourceFrame: CGRect?
    private var didPresentCurrentOverlay = false
    private var tickCounter = 0

    private var onGranted: (() -> Void)?
    private var onCancel: (() -> Void)?

    private init() {}

    // MARK: - 对外 API

    /// 弹出气泡引导用户授权。
    /// - Parameters:
    ///   - panel: 要引导用户去授权的具体面板（屏幕录制 / 辅助功能）。
    ///   - sourceFrameInScreen: 弹跳动画的起点（屏幕坐标）；传 nil 直接淡入。
    ///   - onGranted: 授权检测到通过时调用，气泡已 dismiss。
    ///   - onCancel: 用户点 ← 返回时调用，气泡已 dismiss。
    func present(panel: PermissionPanel,
                 from sourceFrameInScreen: CGRect? = nil,
                 onGranted: (() -> Void)? = nil,
                 onCancel: (() -> Void)? = nil)
    {
        // 已有气泡时先收掉，避免叠加
        dismiss()

        activePanel = panel
        pendingSourceFrame = sourceFrameInScreen
        didPresentCurrentOverlay = false
        tickCounter = 0
        self.onGranted = onGranted
        self.onCancel = onCancel

        let host = PermissionHostApp.current()
        overlay = PermissionOverlayController(hostApp: host, panel: panel) { [weak self] in
            // 用户点 ← 返回
            self?.handleCancel()
        }

        _ = NSWorkspace.shared.open(panel.settingsURL)
        startTracking()
    }

    /// 外部主动 dismiss（不触发 onGranted / onCancel）。
    func dismiss() {
        trackingTimer?.invalidate()
        trackingTimer = nil
        if let obs = activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            activationObserver = nil
        }
        overlay?.close()
        overlay = nil
        activePanel = nil
        pendingSourceFrame = nil
        didPresentCurrentOverlay = false
        onGranted = nil
        onCancel = nil
    }

    // MARK: - 内部跟踪

    private func startTracking() {
        trackingTimer?.invalidate()

        // 单 timer：每 150ms tick 一次，做"窗口跟随 + 周期授权检测"。
        let timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) {
            [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        trackingTimer = timer

        // 系统设置激活变化时也立刻刷一次（不要等 timer 的下一拍），减少视觉延迟。
        if let obs = activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshPosition() }
        }

        refreshPosition()
    }

    private func tick() {
        refreshPosition()

        // 每 3 tick (~450ms) 检测一次授权状态
        tickCounter += 1
        if tickCounter % 3 == 0, let panel = activePanel, hasGranted(panel: panel) {
            handleGranted()
        }
    }

    /// 检测当前 panel 对应的权限是否已被授予。
    /// - screenRecording: `CGPreflightScreenCaptureAccess()`（首次调用也会触发 TCC 注册）。
    /// - accessibility:    `AXIsProcessTrusted()`。
    private func hasGranted(panel: PermissionPanel) -> Bool {
        switch panel {
        case .screenRecording: return CGPreflightScreenCaptureAccess()
        case .accessibility:   return AXIsProcessTrusted()
        }
    }

    private func refreshPosition() {
        guard let overlay else { return }
        guard let snapshot = SettingsWindowLocator.frontmostWindow() else {
            // 系统设置不在前台 → 气泡隐藏，但不结束流程（用户可能切回来继续操作）。
            overlay.hide()
            return
        }
        if didPresentCurrentOverlay {
            overlay.updatePosition(with: snapshot.frame, visibleFrame: snapshot.visibleFrame)
            return
        }
        // 第一次出现：用弹跳飞出动画
        overlay.present(from: pendingSourceFrame,
                        settingsFrame: snapshot.frame,
                        visibleFrame: snapshot.visibleFrame)
        didPresentCurrentOverlay = true
    }

    private func handleGranted() {
        let callback = onGranted
        dismiss()
        callback?()
    }

    private func handleCancel() {
        let callback = onCancel
        dismiss()
        callback?()
    }
}
