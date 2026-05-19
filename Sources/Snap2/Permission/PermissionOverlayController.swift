import AppKit
import Foundation
import QuartzCore

/// 紧贴系统设置窗口下方的悬浮气泡。
///
/// 容器复用项目自身的 GlassPanel（borderless + nonactivating + 跨 Space），不在这里重写
/// 一份 NSPanel。窗口 level 强制 `.statusBar`，避免 GlassPanel 默认的 `.screenSaver+1`
/// 把系统设置遮住——用户拖图标时必须看得到目标列表。
///
/// 动画照搬 Permiso：CADisplayLink 每帧推进，位置走二次贝塞尔曲线（小弧度上抛），
/// 进度走临界阻尼 spring（response = 0.72），不是简单的线性插值——这样能模拟"从触发
/// 按钮飞出、轻盈落到设置下方"的物理感。
final class PermissionOverlayController: NSWindowController {

    private let panelSize = NSSize(width: 510, height: 112)
    private let launchDuration: TimeInterval = 0.72
    private let launchResponse: Double = 0.72
    private let launchDampingFraction: Double = 1.0
    private let initialAlpha: CGFloat = 0.9

    private var launchDisplayLink: CADisplayLink?
    private var launchStartTime: CFTimeInterval = 0
    private var launchFromFrame: NSRect = .zero
    private var launchToFrame: NSRect = .zero
    private var isAnimatingLaunch = false

    init(hostApp: PermissionHostApp, panel: PermissionPanel, onBack: @escaping () -> Void) {
        let glassPanel = GlassPanel(
            size: panelSize,
            cornerRadius: Glass.radiusCard,
            level: .statusBar    // 浮在系统设置之上但不抢菜单栏菜单
        )
        super.init(window: glassPanel)

        let content = OverlayContentView(hostApp: hostApp, panel: panel, onBack: onBack)
        content.frame = glassPanel.contentBox.bounds
        content.autoresizingMask = [.width, .height]
        glassPanel.contentBox.addSubview(content)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - 生命周期

    override func close() {
        stopLaunchAnimation()
        window?.orderOut(nil)
        super.close()
    }

    /// 第一次出现：从 sourceFrameInScreen（如果给了）弹跳飞到 settingsFrame 下方。
    /// sourceFrameInScreen 传 nil 时跳过动画，直接淡入到目标位置。
    func present(from sourceFrameInScreen: CGRect?,
                 settingsFrame: CGRect,
                 visibleFrame: CGRect)
    {
        stopLaunchAnimation()
        guard let window else { return }

        let targetOrigin = anchoredOrigin(for: settingsFrame, visibleFrame: visibleFrame)
        let targetFrame = NSRect(origin: targetOrigin, size: panelSize)

        guard let source = sourceFrameInScreen, !source.isEmpty else {
            // 没有起点：直接落位 + 淡入（运行时拦截场景）
            isAnimatingLaunch = false
            window.alphaValue = 0
            window.setFrame(targetFrame, display: false)
            window.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = 1
            })
            return
        }

        isAnimatingLaunch = true
        launchFromFrame = source
        launchToFrame = targetFrame
        launchStartTime = CACurrentMediaTime()

        window.alphaValue = initialAlpha
        window.setFrame(source, display: false)
        window.orderFrontRegardless()
        stepLaunchAnimation()

        let link = window.displayLink(target: self, selector: #selector(displayLinkDidFire(_:)))
        link.add(to: .main, forMode: .common)
        launchDisplayLink = link
    }

    /// 系统设置窗口被拖动 / 切换激活 / 切换 Space 后，刷新气泡位置。
    /// 动画进行中不打断 —— 落位后下一次 updatePosition 才会贴回新坐标。
    func updatePosition(with settingsFrame: CGRect, visibleFrame: CGRect) {
        guard let window else { return }
        let origin = anchoredOrigin(for: settingsFrame, visibleFrame: visibleFrame)
        launchToFrame.origin = origin
        guard !isAnimatingLaunch else { return }
        window.setFrameOrigin(origin)
        window.orderFrontRegardless()
    }

    /// 系统设置离开前台 → 气泡也隐藏，避免它孤零零浮在桌面上。
    func hide() {
        isAnimatingLaunch = false
        stopLaunchAnimation()
        window?.orderOut(nil)
    }

    // MARK: - 动画

    @objc private func displayLinkDidFire(_ link: CADisplayLink) {
        stepLaunchAnimation()
    }

    private func stepLaunchAnimation() {
        guard let window else { stopLaunchAnimation(); return }
        let elapsed = max(0, CACurrentMediaTime() - launchStartTime)
        if elapsed >= launchDuration {
            isAnimatingLaunch = false
            stopLaunchAnimation()
            window.alphaValue = 1
            window.setFrame(launchToFrame, display: true)
            return
        }
        let progress = springProgress(at: elapsed)
        window.alphaValue = initialAlpha + ((1 - initialAlpha) * progress)
        window.setFrame(curvedFrame(from: launchFromFrame,
                                    to: launchToFrame,
                                    progress: progress),
                        display: true)
    }

    private func stopLaunchAnimation() {
        launchDisplayLink?.invalidate()
        launchDisplayLink = nil
    }

    /// 临界阻尼弹簧的进度曲线。response = 0.72 对应 SwiftUI 默认 spring 的"中等弹性"。
    /// 公式 1 − e^(−ωt)(1 + ωt) 是临界阻尼解析解，永远在 [0, 1) 单调上升，不会过冲。
    private func springProgress(at elapsed: TimeInterval) -> CGFloat {
        let omega = (2 * Double.pi) / launchResponse
        let t = max(0, elapsed)
        let progress: Double
        if abs(launchDampingFraction - 1) < 0.0001 {
            progress = 1 - exp(-omega * t) * (1 + (omega * t))
        } else {
            progress = min(1, t / launchDuration)
        }
        return min(max(progress, 0), 1)
    }

    /// 从起点到终点的二次贝塞尔曲线 + 小弧度上抛。
    /// 控制点选在两点中点上方 lift 像素，让气泡"先上扬再落下"，更接近 Codex 原版手感。
    private func curvedFrame(from src: NSRect, to dst: NSRect, progress: CGFloat) -> NSRect {
        let size = NSSize(
            width: src.size.width + (dst.size.width - src.size.width) * progress,
            height: src.size.height + (dst.size.height - src.size.height) * progress
        )
        let s = CGPoint(x: src.midX, y: src.midY)
        let e = CGPoint(x: dst.midX, y: dst.midY)
        let mid = CGPoint(x: (s.x + e.x) * 0.5, y: max(s.y, e.y))

        let distance = hypot(e.x - s.x, e.y - s.y)
        let lift = min(140, max(44, distance * 0.18))
        let cp = CGPoint(x: mid.x, y: mid.y + lift)
        let inv = 1 - progress
        let center = CGPoint(
            x: inv * inv * s.x + 2 * inv * progress * cp.x + progress * progress * e.x,
            y: inv * inv * s.y + 2 * inv * progress * cp.y + progress * progress * e.y
        )
        return NSRect(
            x: center.x - size.width * 0.5,
            y: center.y - size.height * 0.5,
            width: size.width,
            height: size.height
        )
    }

    /// 算气泡的"落位"——贴在系统设置窗口正下方、内容区中线对齐、留 14pt 间距。
    /// `sidebarWidth = 170` 是系统设置左侧栏宽度的近似值，让箭头能指向"屏幕录制"
    /// 列表所在的内容区中线而不是整窗中心。
    private func anchoredOrigin(for settingsFrame: CGRect,
                                 visibleFrame: CGRect) -> NSPoint
    {
        let sidebarWidth: CGFloat = 170
        let contentMinX = settingsFrame.minX + sidebarWidth
        let contentWidth = max(settingsFrame.width - sidebarWidth, panelSize.width)
        let preferredX = contentMinX + (contentWidth - panelSize.width) / 2 - 8
        let preferredY = settingsFrame.minY + 14

        let minX = visibleFrame.minX + 8
        let maxX = visibleFrame.maxX - panelSize.width - 8
        let minY = visibleFrame.minY + 8
        let maxY = visibleFrame.maxY - panelSize.height - 8

        return NSPoint(
            x: min(max(preferredX, minX), maxX),
            y: min(max(preferredY, minY), maxY)
        )
    }
}

// MARK: - 气泡内容布局

private final class OverlayContentView: NSView {
    private let onBack: () -> Void

    init(hostApp: PermissionHostApp, panel: PermissionPanel, onBack: @escaping () -> Void) {
        self.onBack = onBack
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        build(hostApp: hostApp, panel: panel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build(hostApp: PermissionHostApp, panel: PermissionPanel) {
        // 左侧 ← 返回按钮 ——————————————————————————
        let backChrome = NSView()
        backChrome.translatesAutoresizingMaskIntoConstraints = false
        backChrome.wantsLayer = true
        backChrome.layer?.backgroundColor = Glass.hoverFill.cgColor
        backChrome.layer?.cornerRadius = Glass.radiusButton
        addSubview(backChrome)

        let backButton = NSButton()
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.isBordered = false
        backButton.image = NSImage(systemSymbolName: "chevron.left",
                                   accessibilityDescription: "返回")
        backButton.contentTintColor = NSColor.white.withAlphaComponent(0.78)
        backButton.target = self
        backButton.action = #selector(backPressed)
        if let cell = backButton.cell as? NSButtonCell {
            cell.imagePosition = .imageOnly
        }
        backChrome.addSubview(backButton)

        // ↑ 蓝色箭头 ——————————————————————————
        let arrowView = NSImageView()
        arrowView.translatesAutoresizingMaskIntoConstraints = false
        arrowView.image = NSImage(systemSymbolName: "arrow.up", accessibilityDescription: nil)
        arrowView.symbolConfiguration = .init(pointSize: 26, weight: .bold)
        arrowView.contentTintColor = ClaudeTheme.accent

        addSubview(arrowView)

        // 中文标题 ——————————————————————————
        let titleLabel = NSTextField(labelWithAttributedString:
            title(hostApp: hostApp, panel: panel))
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.maximumNumberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        // 拖拽行 ——————————————————————————
        let dragSource = PermissionDragSourceView(hostApp: hostApp)
        addSubview(dragSource)

        NSLayoutConstraint.activate([
            // 返回按钮位于左下，远离箭头
            backChrome.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            backChrome.topAnchor.constraint(equalTo: topAnchor, constant: 52),
            backChrome.widthAnchor.constraint(equalToConstant: 30),
            backChrome.heightAnchor.constraint(equalToConstant: 30),
            backButton.centerXAnchor.constraint(equalTo: backChrome.centerXAnchor),
            backButton.centerYAnchor.constraint(equalTo: backChrome.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 13),
            backButton.heightAnchor.constraint(equalToConstant: 13),

            // 箭头位于左上、与标题首字基线对齐
            arrowView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            arrowView.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            arrowView.widthAnchor.constraint(equalToConstant: 26),
            arrowView.heightAnchor.constraint(equalToConstant: 26),

            titleLabel.leadingAnchor.constraint(equalTo: arrowView.trailingAnchor, constant: 10),
            titleLabel.centerYAnchor.constraint(equalTo: arrowView.centerYAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -22),

            // 拖拽行位于下半部分，挪到 backChrome 右侧
            dragSource.leadingAnchor.constraint(equalTo: backChrome.trailingAnchor, constant: 10),
            dragSource.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            dragSource.centerYAnchor.constraint(equalTo: backChrome.centerYAnchor),
            dragSource.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    private func title(hostApp: PermissionHostApp,
                       panel: PermissionPanel) -> NSAttributedString
    {
        let text = "拖拽 \(hostApp.displayName) 到上方列表以授予\(panel.title)权限"
        return NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.92),
        ])
    }

    @objc private func backPressed() { onBack() }
}
