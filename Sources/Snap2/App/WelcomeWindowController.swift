import AppKit

/// 首启欢迎窗口 — 液态玻璃风格。
final class WelcomeWindowController: NSWindowController {

    private var onComplete: (() -> Void)?

    /// 主按钮 / 提示 label 引用，授权流程里用来切换文案
    private weak var startButton: WelcomeAccentButton?
    private weak var permLabel: NSTextField?

    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete

        let size = NSSize(width: 620, height: 580)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "欢迎使用 Snap²"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.center()
        window.backgroundColor = .clear
        // 跟随系统明暗
        window.appearance = nil

        super.init(window: window)
        setupContent(size: size)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setupContent(size: NSSize) {
        guard let contentView = window?.contentView else { return }

        // 全屏液态玻璃底（米白 tint + 顶光 + 底暖光，自动跟随系统明暗）
        ClaudeGlass.install(into: contentView)

        // 顶部 Logo + 标题
        let badge = NSTextField(labelWithString: "首次启动引导")
        badge.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        badge.textColor = ClaudeTheme.accent
        badge.alignment = .center
        badge.backgroundColor = .clear
        badge.wantsLayer = true
        badge.layer?.backgroundColor = ClaudeTheme.accent.withAlphaComponent(0.10).cgColor
        badge.layer?.cornerRadius = 10
        badge.layer?.cornerCurve = .continuous
        badge.frame = NSRect(x: (size.width - 100) / 2, y: size.height - 58, width: 100, height: 22)
        contentView.addSubview(badge)

        let logoSize: CGFloat = 88
        let logoY = size.height - 172
        let logo = AppearanceAwareView { v in
            v.layer?.backgroundColor = ClaudeTheme.accent.cgColor
            v.layer?.borderColor = NSColor.white.withAlphaComponent(0.40).cgColor
        }
        logo.frame = NSRect(x: (size.width - logoSize) / 2, y: logoY, width: logoSize, height: logoSize)
        logo.wantsLayer = true
        logo.layer?.cornerRadius = 22
        logo.layer?.borderWidth = 1
        contentView.addSubview(logo)

        let icon = NSImageView(frame: NSRect(x: 0, y: 0, width: logoSize, height: logoSize))
        if let img = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: nil) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 44, weight: .light)
            icon.image = img.withSymbolConfiguration(cfg)
            icon.contentTintColor = .white
        }
        logo.addSubview(icon)

        let title = NSTextField(labelWithString: "Snap²")
        title.font = NSFont.systemFont(ofSize: 34, weight: .semibold)
        title.textColor = ClaudeTheme.ink
        title.backgroundColor = .clear
        title.alignment = .center
        title.frame = NSRect(x: 0, y: logoY - 54, width: size.width, height: 42)
        contentView.addSubview(title)

        let subtitle = NSTextField(labelWithString: "轻盈、快捷、带即时标注能力的 macOS 截图工作台")
        subtitle.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        subtitle.textColor = ClaudeTheme.inkSecondary
        subtitle.backgroundColor = .clear
        subtitle.alignment = .center
        subtitle.frame = NSRect(x: 54, y: logoY - 82, width: size.width - 108, height: 22)
        contentView.addSubview(subtitle)

        let intro = NSTextField(labelWithString: "区域截图、标注、复制与保存都在一次操作里完成")
        intro.font = NSFont.systemFont(ofSize: 12)
        intro.textColor = ClaudeTheme.inkTertiary
        intro.backgroundColor = .clear
        intro.alignment = .center
        intro.frame = NSRect(x: 54, y: logoY - 104, width: size.width - 108, height: 18)
        contentView.addSubview(intro)

        // 功能格子
        let features: [(String, String, String)] = [
            ("crop", "区域截图", "拖拽框选，松手即进标注"),
            ("scribble.variable", "实时标注", "箭头、矩形、画笔、文字…"),
            ("doc.on.clipboard", "一键复制", "Enter 复制到剪贴板"),
            // 当前 7 个工具：箭头/矩形/椭圆/画笔/文字/高亮/马赛克
            ("keyboard", "全键盘", "1-7 切工具，⌘Z 撤销"),
        ]

        let cellW: CGFloat = 252
        let cellH: CGFloat = 78
        let gridY: CGFloat = 182
        for (i, item) in features.enumerated() {
            let row = i / 2, col = i % 2
            let x = (size.width - cellW * 2 - 16) / 2 + CGFloat(col) * (cellW + 16)
            let y = gridY + CGFloat(1 - row) * (cellH + 14)
            addFeatureCell(in: contentView,
                           frame: NSRect(x: x, y: y, width: cellW, height: cellH),
                           symbol: item.0, title: item.1, desc: item.2)
        }

        // 权限提示
        let permBox = AppearanceAwareView { v in
            v.layer?.backgroundColor = ClaudeTheme.creamCard.cgColor
            v.layer?.borderColor = ClaudeTheme.stroke.cgColor
        }
        permBox.frame = NSRect(x: 52, y: 88, width: size.width - 104, height: 76)
        permBox.wantsLayer = true
        permBox.layer?.cornerRadius = 16
        permBox.layer?.borderWidth = 1
        permBox.layer?.shadowColor = ClaudeTheme.accent.withAlphaComponent(0.10).cgColor
        permBox.layer?.shadowOpacity = 1.0
        permBox.layer?.shadowRadius = 10
        permBox.layer?.shadowOffset = CGSize(width: 0, height: -2)
        contentView.addSubview(permBox)

        let permIcon = NSImageView(frame: NSRect(x: 16, y: 25, width: 24, height: 24))
        if let img = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: nil) {
            permIcon.image = img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .medium))
            permIcon.contentTintColor = ClaudeTheme.accent
        }
        permBox.addSubview(permIcon)

        let permTitle = NSTextField(labelWithString: "完成屏幕录制权限授权")
        permTitle.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        permTitle.textColor = ClaudeTheme.ink
        permTitle.backgroundColor = .clear
        permTitle.frame = NSRect(x: 48, y: 39, width: permBox.frame.width - 62, height: 18)
        permBox.addSubview(permTitle)

        let permLabel = NSTextField(labelWithString: "需要「屏幕录制」权限。点击下方按钮后，将打开系统设置授权。")
        permLabel.font = NSFont.systemFont(ofSize: 11)
        permLabel.textColor = ClaudeTheme.inkSecondary
        permLabel.backgroundColor = .clear
        permLabel.maximumNumberOfLines = 2
        permLabel.lineBreakMode = .byWordWrapping
        permLabel.frame = NSRect(x: 48, y: 14, width: permBox.frame.width - 64, height: 24)
        permBox.addSubview(permLabel)
        self.permLabel = permLabel

        // 主按钮（玻璃强调）
        let buttonW: CGFloat = 240, buttonH: CGFloat = 42
        let btn = WelcomeAccentButton(frame: NSRect(
            x: (size.width - buttonW) / 2, y: 30, width: buttonW, height: buttonH))
        btn.title = "授权并开始使用"
        btn.target = self
        btn.action = #selector(startTapped)
        contentView.addSubview(btn)
        self.startButton = btn

        let footnote = NSTextField(labelWithString: "授权完成后将自动继续，无需重启应用")
        footnote.font = NSFont.systemFont(ofSize: 11)
        footnote.textColor = ClaudeTheme.inkTertiary
        footnote.alignment = .center
        footnote.backgroundColor = .clear
        footnote.frame = NSRect(x: 0, y: 10, width: size.width, height: 16)
        contentView.addSubview(footnote)
    }

    private func addFeatureCell(in container: NSView, frame: NSRect, symbol: String, title: String, desc: String) {
        let cell = AppearanceAwareView { v in
            v.layer?.backgroundColor = ClaudeTheme.creamCard.cgColor
            v.layer?.borderColor = ClaudeTheme.stroke.cgColor
        }
        cell.frame = frame
        cell.wantsLayer = true
        cell.layer?.cornerRadius = 16
        cell.layer?.cornerCurve = .continuous
        cell.layer?.borderWidth = 1
        cell.layer?.shadowColor = ClaudeTheme.accent.withAlphaComponent(0.08).cgColor
        cell.layer?.shadowOpacity = 1.0
        cell.layer?.shadowRadius = 10
        cell.layer?.shadowOffset = CGSize(width: 0, height: -2)

        let iconBg = AppearanceAwareView { v in
            v.layer?.backgroundColor = ClaudeTheme.accent.withAlphaComponent(0.16).cgColor
        }
        iconBg.frame = NSRect(x: 14, y: (frame.height - 36) / 2, width: 36, height: 36)
        iconBg.wantsLayer = true
        iconBg.layer?.cornerRadius = 11
        cell.addSubview(iconBg)

        let icon = NSImageView(frame: NSRect(x: 0, y: 0, width: 36, height: 36))
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            icon.image = img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .medium))
            icon.contentTintColor = ClaudeTheme.accent
        }
        iconBg.addSubview(icon)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = ClaudeTheme.ink
        titleLabel.backgroundColor = .clear
        titleLabel.frame = NSRect(x: 62, y: frame.height - 33, width: frame.width - 74, height: 18)
        cell.addSubview(titleLabel)

        let descLabel = NSTextField(labelWithString: desc)
        descLabel.font = NSFont.systemFont(ofSize: 11)
        descLabel.textColor = ClaudeTheme.inkSecondary
        descLabel.backgroundColor = .clear
        descLabel.frame = NSRect(x: 62, y: 18, width: frame.width - 74, height: 16)
        cell.addSubview(descLabel)

        container.addSubview(cell)
    }

    @objc private func startTapped() {
        // 已有权限：直接走完成流程
        if CGPreflightScreenCaptureAccess() {
            finishOnboarding()
            return
        }
        beginAwaitingPermission()

        // 弹"拖拽授权"气泡。起点用按钮在屏幕坐标里的 frame，让气泡从按钮位置弹跳飞出。
        // 轮询统一由 PermissionAssistant 管，授权成功走 onGranted，用户点 ← 走 onCancel。
        var sourceFrame: CGRect? = nil
        if let button = startButton, let window = button.window {
            let rectInWindow = button.convert(button.bounds, to: nil)
            sourceFrame = window.convertToScreen(rectInWindow)
        }
        PermissionAssistant.shared.present(
            panel: .screenRecording,
            from: sourceFrame,
            onGranted: { [weak self] in self?.finishOnboarding() },
            onCancel: { [weak self] in self?.resetForPermissionRetry() }
        )
    }

    private func beginAwaitingPermission() {
        startButton?.title = "等待授权…"
        startButton?.attributedTitle = NSAttributedString(
            string: "等待授权…",
            attributes: [
                .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
                .foregroundColor: NSColor.white
            ])
        startButton?.isEnabled = false
        permLabel?.stringValue = "请把图标拖进系统设置的列表，授权完成后将自动继续。"
    }

    private func resetForPermissionRetry() {
        startButton?.isEnabled = true
        startButton?.attributedTitle = NSAttributedString(
            string: "再次尝试授权",
            attributes: [
                .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
                .foregroundColor: NSColor.white
            ])
        permLabel?.stringValue = "未检测到授权。请点击下方按钮重新打开授权引导。"
    }

    private func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: UDKey.hasCompletedOnboarding)
        window?.close()
        SettingsWindowController.shared.showWindow()
        onComplete?()
        onComplete = nil
    }

    func showWindow() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - 玻璃质感主按钮

final class WelcomeAccentButton: NSButton {

    private let bgLayer = CAGradientLayer()
    private let strokeLayer = CAShapeLayer()
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private var isPressed = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .inline
        isBordered = false
        wantsLayer = true
        layer?.masksToBounds = false

        layer?.insertSublayer(bgLayer, at: 0)
        layer?.addSublayer(strokeLayer)

        font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        contentTintColor = .white
        keyEquivalent = "\r"
        attributedTitle = NSAttributedString(string: "授权并开始使用",
                                             attributes: [
                                                .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
                                                .foregroundColor: NSColor.white
                                             ])

        bgLayer.startPoint = CGPoint(x: 0.5, y: 1.0)
        bgLayer.endPoint = CGPoint(x: 0.5, y: 0.0)
        strokeLayer.fillColor = .clear
        strokeLayer.lineWidth = 1

        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let a = trackingArea { removeTrackingArea(a) }
        let a = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(a); trackingArea = a
    }
    override func mouseEntered(with event: NSEvent) { isHovered = true; refresh() }
    override func mouseExited(with event: NSEvent)  { isHovered = false; isPressed = false; refresh() }
    override func mouseDown(with event: NSEvent) {
        isPressed = true; refresh()
        super.mouseDown(with: event)
        isPressed = false; refresh()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bgLayer.frame = bounds
        bgLayer.cornerRadius = bounds.height / 2
        strokeLayer.frame = bounds
        let inset: CGFloat = 0.5
        let rect = bounds.insetBy(dx: inset, dy: inset)
        strokeLayer.path = CGPath(roundedRect: rect, cornerWidth: rect.height / 2, cornerHeight: rect.height / 2, transform: nil)
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }

    private func refresh() {
        let topAlpha: CGFloat = isPressed ? 0.85 : (isHovered ? 1.0 : 0.95)
        let botAlpha: CGFloat = isPressed ? 0.65 : (isHovered ? 0.85 : 0.78)

        effectiveAppearance.performAsCurrentDrawingAppearance {
            let accent = isPressed ? ClaudeTheme.accentPressed : ClaudeTheme.accent
            CATransaction.begin()
            CATransaction.setAnimationDuration(Glass.animDuration)
            bgLayer.colors = [
                accent.withAlphaComponent(topAlpha).cgColor,
                accent.withAlphaComponent(botAlpha).cgColor
            ]
            strokeLayer.strokeColor = NSColor.white.withAlphaComponent(0.45).cgColor
            CATransaction.commit()
        }
    }
}
