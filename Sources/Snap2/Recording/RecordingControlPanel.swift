import AppKit

/// 录制中悬浮在屏幕右上角的小控制面板。
///
/// 展示当前录制时长（mm:ss / hh:mm:ss）+ 红色停止按钮。
/// - level = .statusBar + 1：盖过普通浮窗但不抢菜单栏；canBecomeKey = false 不抢焦点
/// - 计时器用 Timer 而非 CADisplayLink——1Hz 更新足够，且 main runloop 即可
/// - 停止：点按钮 → 调 onStop。同时全局热键 / Esc 也走同一回调（在 RecordingManager 里订阅）
final class RecordingControlPanel {

    /// 用户点击"停止"或外部触发停止时的回调
    var onStop: (() -> Void)?

    private let panel: GlassPanel
    private let timeLabel = NSTextField(labelWithString: "00:00")
    private let stopButton = GlassButton(symbol: "stop.fill",
                                         size: 32,
                                         tooltip: "停止录屏")
    private let recordDot = NSView()

    private var timer: Timer?
    private var startedAt: Date?

    init() {
        let size = NSSize(width: 156, height: 44)
        panel = GlassPanel(size: size, cornerRadius: 14, level: .statusBar + 1)

        let host = panel.contentBox

        // 左侧呼吸的红点（recording indicator）
        recordDot.translatesAutoresizingMaskIntoConstraints = false
        recordDot.wantsLayer = true
        recordDot.layer?.backgroundColor = NSColor.systemRed.cgColor
        recordDot.layer?.cornerRadius = 4
        host.addSubview(recordDot)

        // 中间时长 label——等宽字体保证位数变化不抖
        timeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        timeLabel.textColor = .white
        timeLabel.alignment = .center
        timeLabel.backgroundColor = .clear
        timeLabel.isBezeled = false
        timeLabel.isEditable = false
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(timeLabel)

        // 右侧红色停止按钮
        stopButton.accentColor = .systemRed
        stopButton.isDestructive = true
        stopButton.target = self
        stopButton.action = #selector(stopTapped)
        host.addSubview(stopButton)

        NSLayoutConstraint.activate([
            recordDot.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 14),
            recordDot.centerYAnchor.constraint(equalTo: host.centerYAnchor),
            recordDot.widthAnchor.constraint(equalToConstant: 8),
            recordDot.heightAnchor.constraint(equalToConstant: 8),

            timeLabel.leadingAnchor.constraint(equalTo: recordDot.trailingAnchor, constant: 8),
            timeLabel.trailingAnchor.constraint(equalTo: stopButton.leadingAnchor, constant: -8),
            timeLabel.centerYAnchor.constraint(equalTo: host.centerYAnchor),

            stopButton.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -8),
            stopButton.centerYAnchor.constraint(equalTo: host.centerYAnchor),
        ])
    }

    /// 显示在屏幕右上角（与系统通知一致的角落），并开始计时
    func showAndStart(on screen: NSScreen? = nil) {
        let s = screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let visible = s?.visibleFrame else { return }
        let margin: CGFloat = 16
        let origin = NSPoint(
            x: visible.maxX - panel.frame.width - margin,
            y: visible.maxY - panel.frame.height - margin
        )
        panel.alphaValue = 0
        panel.setFrameOrigin(origin)
        panel.orderFront(nil)

        // 入场：从上方滑入（与 CopyToast 一致）
        let from = NSPoint(x: origin.x, y: origin.y + 12)
        panel.setFrameOrigin(from)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1.0
            panel.animator().setFrameOrigin(origin)
        }, completionHandler: nil)

        // 启动 1Hz 计时器；用 CommonRunLoop 模式，菜单弹出 / drag tracking 期间也走
        startedAt = Date()
        timer?.invalidate()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()  // 先刷一次到 00:00
        animateRecordDot()
    }

    func dismiss(_ completion: (() -> Void)? = nil) {
        timer?.invalidate()
        timer = nil
        recordDot.layer?.removeAllAnimations()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [panel] in
            panel.orderOut(nil)
            completion?()
        })
    }

    // MARK: - Private

    @objc private func stopTapped() {
        // 异步派发——和别处一样，避免在 NSButton mouseDown loop 内自释/拆窗
        DispatchQueue.main.async { [weak self] in
            self?.onStop?()
        }
    }

    private func tick() {
        guard let start = startedAt else { return }
        let elapsed = Int(Date().timeIntervalSince(start))
        let h = elapsed / 3600
        let m = (elapsed % 3600) / 60
        let s = elapsed % 60
        if h > 0 {
            timeLabel.stringValue = String(format: "%d:%02d:%02d", h, m, s)
        } else {
            timeLabel.stringValue = String(format: "%02d:%02d", m, s)
        }
    }

    /// 红点呼吸动画：透明度在 [0.35, 1.0] 之间往复，提示"正在录制"
    private func animateRecordDot() {
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = 1.0
        anim.toValue = 0.35
        anim.duration = 0.9
        anim.autoreverses = true
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        recordDot.layer?.add(anim, forKey: "breathing")
    }
}
