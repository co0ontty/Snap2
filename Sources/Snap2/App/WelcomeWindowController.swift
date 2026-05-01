import AppKit

/// 首启欢迎窗口 — 液态玻璃风格。
final class WelcomeWindowController: NSWindowController {

    private var onComplete: (() -> Void)?

    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete

        let size = NSSize(width: 560, height: 520)
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
        window.appearance = NSAppearance(named: .vibrantDark)

        super.init(window: window)
        setupContent(size: size)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setupContent(size: NSSize) {
        guard let contentView = window?.contentView else { return }

        // 全屏液态玻璃底
        let blur = NSVisualEffectView(frame: contentView.bounds)
        blur.material = .underWindowBackground
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.autoresizingMask = [.width, .height]
        contentView.addSubview(blur)

        // 顶部柔和高光
        let highlightHost = NSView(frame: contentView.bounds)
        highlightHost.autoresizingMask = [.width, .height]
        highlightHost.wantsLayer = true
        let highlight = CAGradientLayer()
        highlight.colors = [
            NSColor.white.withAlphaComponent(0.22).cgColor,
            NSColor.white.withAlphaComponent(0.0).cgColor,
        ]
        highlight.locations = [0.0, 1.0]
        highlight.startPoint = CGPoint(x: 0.5, y: 1.0)
        highlight.endPoint = CGPoint(x: 0.5, y: 0.45)
        highlight.frame = highlightHost.bounds
        highlightHost.layer?.addSublayer(highlight)
        contentView.addSubview(highlightHost)

        // 顶部 Logo + 标题
        let logoSize: CGFloat = 84
        let logoY = size.height - 152
        let logo = NSView(frame: NSRect(x: (size.width - logoSize) / 2, y: logoY, width: logoSize, height: logoSize))
        logo.wantsLayer = true
        logo.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
        logo.layer?.cornerRadius = 22
        logo.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        logo.layer?.borderWidth = 1
        contentView.addSubview(logo)

        let icon = NSImageView(frame: NSRect(x: 0, y: 0, width: logoSize, height: logoSize))
        if let img = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: nil) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 44, weight: .light)
            icon.image = img.withSymbolConfiguration(cfg)
            icon.contentTintColor = NSColor.white.withAlphaComponent(0.95)
        }
        logo.addSubview(icon)

        let title = NSTextField(labelWithString: "Snap²")
        title.font = NSFont.systemFont(ofSize: 32, weight: .semibold)
        title.textColor = NSColor.white
        title.backgroundColor = .clear
        title.alignment = .center
        title.frame = NSRect(x: 0, y: logoY - 50, width: size.width, height: 40)
        contentView.addSubview(title)

        let subtitle = NSTextField(labelWithString: "轻盈快捷的 macOS 截图标注工具")
        subtitle.font = NSFont.systemFont(ofSize: 13)
        subtitle.textColor = NSColor.white.withAlphaComponent(0.65)
        subtitle.backgroundColor = .clear
        subtitle.alignment = .center
        subtitle.frame = NSRect(x: 0, y: logoY - 74, width: size.width, height: 22)
        contentView.addSubview(subtitle)

        // 功能格子
        let features: [(String, String, String)] = [
            ("crop", "区域截图", "拖拽框选，松手即进标注"),
            ("scribble.variable", "实时标注", "箭头、矩形、画笔、文字…"),
            ("doc.on.clipboard", "一键复制", "Enter 复制到剪贴板"),
            ("keyboard", "全键盘", "1-6 切工具，⌘Z 撤销"),
        ]

        let cellW: CGFloat = 232
        let cellH: CGFloat = 64
        let gridY: CGFloat = 150
        for (i, item) in features.enumerated() {
            let row = i / 2, col = i % 2
            let x = (size.width - cellW * 2 - 14) / 2 + CGFloat(col) * (cellW + 14)
            let y = gridY + CGFloat(1 - row) * (cellH + 12)
            addFeatureCell(in: contentView,
                           frame: NSRect(x: x, y: y, width: cellW, height: cellH),
                           symbol: item.0, title: item.1, desc: item.2)
        }

        // 权限提示
        let permBox = NSView(frame: NSRect(x: 60, y: 78, width: size.width - 120, height: 48))
        permBox.wantsLayer = true
        permBox.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        permBox.layer?.cornerRadius = 14
        permBox.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        permBox.layer?.borderWidth = 1
        contentView.addSubview(permBox)

        let permIcon = NSImageView(frame: NSRect(x: 14, y: 12, width: 24, height: 24))
        if let img = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: nil) {
            permIcon.image = img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .medium))
            permIcon.contentTintColor = NSColor.white.withAlphaComponent(0.8)
        }
        permBox.addSubview(permIcon)

        let permLabel = NSTextField(labelWithString: "需要「屏幕录制」权限。点击下方按钮后，将打开系统设置授权。")
        permLabel.font = NSFont.systemFont(ofSize: 11)
        permLabel.textColor = NSColor.white.withAlphaComponent(0.72)
        permLabel.backgroundColor = .clear
        permLabel.frame = NSRect(x: 46, y: 14, width: permBox.frame.width - 60, height: 20)
        permBox.addSubview(permLabel)

        // 主按钮（玻璃强调）
        let buttonW: CGFloat = 220, buttonH: CGFloat = 40
        let btn = WelcomeAccentButton(frame: NSRect(
            x: (size.width - buttonW) / 2, y: 20, width: buttonW, height: buttonH))
        btn.title = "授权并开始使用"
        btn.target = self
        btn.action = #selector(startTapped)
        contentView.addSubview(btn)
    }

    private func addFeatureCell(in container: NSView, frame: NSRect, symbol: String, title: String, desc: String) {
        let cell = NSView(frame: frame)
        cell.wantsLayer = true
        cell.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
        cell.layer?.cornerRadius = 14
        cell.layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        cell.layer?.borderWidth = 1

        let iconBg = NSView(frame: NSRect(x: 12, y: (frame.height - 32) / 2, width: 32, height: 32))
        iconBg.wantsLayer = true
        iconBg.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
        iconBg.layer?.cornerRadius = 9
        cell.addSubview(iconBg)

        let icon = NSImageView(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            icon.image = img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .medium))
            icon.contentTintColor = NSColor.white.withAlphaComponent(0.92)
        }
        iconBg.addSubview(icon)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = NSColor.white.withAlphaComponent(0.95)
        titleLabel.backgroundColor = .clear
        titleLabel.frame = NSRect(x: 54, y: frame.height - 30, width: frame.width - 64, height: 18)
        cell.addSubview(titleLabel)

        let descLabel = NSTextField(labelWithString: desc)
        descLabel.font = NSFont.systemFont(ofSize: 11)
        descLabel.textColor = NSColor.white.withAlphaComponent(0.62)
        descLabel.backgroundColor = .clear
        descLabel.frame = NSRect(x: 54, y: 10, width: frame.width - 64, height: 16)
        cell.addSubview(descLabel)

        container.addSubview(cell)
    }

    @objc private func startTapped() {
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
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

    private func refresh() {
        let accent = NSColor.controlAccentColor
        let topAlpha: CGFloat = isPressed ? 0.85 : (isHovered ? 1.0 : 0.95)
        let botAlpha: CGFloat = isPressed ? 0.65 : (isHovered ? 0.85 : 0.78)

        CATransaction.begin()
        CATransaction.setAnimationDuration(Glass.animDuration)
        bgLayer.colors = [
            accent.withAlphaComponent(topAlpha).cgColor,
            accent.withAlphaComponent(botAlpha).cgColor
        ]
        strokeLayer.strokeColor = NSColor.white.withAlphaComponent(0.30).cgColor
        CATransaction.commit()
    }
}
