import AppKit

/// 首启欢迎窗口 — 扁平原生风。
final class WelcomeWindowController: NSWindowController {

    private var onComplete: (() -> Void)?

    /// 主按钮 / 提示 label 引用，授权流程里用来切换文案
    private weak var startButton: NSButton?
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
        window.backgroundColor = .windowBackgroundColor
        // 跟随系统明暗
        window.appearance = nil

        super.init(window: window)
        setupContent(size: size)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setupContent(size: NSSize) {
        guard let contentView = window?.contentView else { return }

        // 整列用 Auto Layout 纵向排布，换文案/换语言不会错位
        let column = NSStackView()
        column.orientation = .vertical
        column.alignment = .centerX
        column.spacing = 12
        column.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(column)

        // 顶部提示 + Logo + 标题
        let badge = NSTextField(labelWithString: "首次启动引导")
        badge.font = NSFont.systemFont(ofSize: 11)
        badge.textColor = .tertiaryLabelColor
        badge.alignment = .center
        badge.backgroundColor = .clear
        column.addArrangedSubview(badge)
        column.setCustomSpacing(12, after: badge)

        let logo = NSImageView()
        logo.image = NSApplication.shared.applicationIconImage
        logo.imageScaling = .scaleProportionallyUpOrDown
        logo.translatesAutoresizingMaskIntoConstraints = false
        logo.widthAnchor.constraint(equalToConstant: 80).isActive = true
        logo.heightAnchor.constraint(equalToConstant: 80).isActive = true
        column.addArrangedSubview(logo)
        column.setCustomSpacing(14, after: logo)

        let title = NSTextField(labelWithString: "Snap²")
        title.font = NSFont.systemFont(ofSize: 28, weight: .semibold)
        title.textColor = .labelColor
        title.backgroundColor = .clear
        title.alignment = .center
        column.addArrangedSubview(title)
        column.setCustomSpacing(6, after: title)

        let subtitle = NSTextField(labelWithString: "轻盈、快捷、带即时标注能力的 macOS 截图工作台")
        subtitle.font = NSFont.systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor
        subtitle.backgroundColor = .clear
        subtitle.alignment = .center
        column.addArrangedSubview(subtitle)
        column.setCustomSpacing(4, after: subtitle)

        let intro = NSTextField(labelWithString: "区域截图、标注、复制与保存都在一次操作里完成")
        intro.font = NSFont.systemFont(ofSize: 12)
        intro.textColor = .tertiaryLabelColor
        intro.backgroundColor = .clear
        intro.alignment = .center
        column.addArrangedSubview(intro)
        column.setCustomSpacing(18, after: intro)

        // 功能格子（扁平：纯图标 + 文字，轻底色）
        let features: [(String, String, String)] = [
            ("crop", "区域截图", "拖拽框选，松手即进标注"),
            ("scribble.variable", "实时标注", "箭头、矩形、画笔、文字…"),
            ("doc.on.clipboard", "一键复制", "Enter 复制到剪贴板"),
            // 当前 7 个工具：箭头/矩形/椭圆/画笔/文字/高亮/马赛克
            ("keyboard", "全键盘", "1-7 切工具，⌘Z 撤销"),
        ]

        let grid = NSGridView()
        grid.columnSpacing = 12
        grid.rowSpacing = 12
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.addRow(with: [makeFeatureCell(symbol: features[0].0, title: features[0].1, desc: features[0].2),
                           makeFeatureCell(symbol: features[1].0, title: features[1].1, desc: features[1].2)])
        grid.addRow(with: [makeFeatureCell(symbol: features[2].0, title: features[2].1, desc: features[2].2),
                           makeFeatureCell(symbol: features[3].0, title: features[3].1, desc: features[3].2)])
        column.addArrangedSubview(grid)
        column.setCustomSpacing(18, after: grid)

        // 权限提示（扁平）
        let permBox = AppearanceAwareView { v in
            v.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.30).cgColor
        }
        permBox.translatesAutoresizingMaskIntoConstraints = false
        permBox.wantsLayer = true
        permBox.layer?.cornerRadius = 8
        permBox.layer?.cornerCurve = .continuous
        column.addArrangedSubview(permBox)
        column.setCustomSpacing(16, after: permBox)

        let permIcon = NSImageView()
        if let img = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: nil) {
            permIcon.image = img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .medium))
            permIcon.contentTintColor = .controlAccentColor
        }
        permIcon.translatesAutoresizingMaskIntoConstraints = false
        permBox.addSubview(permIcon)

        let permTitle = NSTextField(labelWithString: "完成屏幕录制权限授权")
        permTitle.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        permTitle.textColor = .labelColor
        permTitle.backgroundColor = .clear
        permTitle.translatesAutoresizingMaskIntoConstraints = false
        permBox.addSubview(permTitle)

        let permLabel = NSTextField(labelWithString: "需要「屏幕录制」权限。点击下方按钮后，将打开系统设置授权。")
        permLabel.font = NSFont.systemFont(ofSize: 11)
        permLabel.textColor = .secondaryLabelColor
        permLabel.backgroundColor = .clear
        permLabel.maximumNumberOfLines = 2
        permLabel.lineBreakMode = .byWordWrapping
        permLabel.translatesAutoresizingMaskIntoConstraints = false
        permBox.addSubview(permLabel)
        self.permLabel = permLabel

        NSLayoutConstraint.activate([
            permBox.widthAnchor.constraint(equalTo: grid.widthAnchor),
            permBox.heightAnchor.constraint(equalToConstant: 68),

            permIcon.leadingAnchor.constraint(equalTo: permBox.leadingAnchor, constant: 14),
            permIcon.centerYAnchor.constraint(equalTo: permBox.centerYAnchor),
            permIcon.widthAnchor.constraint(equalToConstant: 24),
            permIcon.heightAnchor.constraint(equalToConstant: 24),

            permTitle.leadingAnchor.constraint(equalTo: permIcon.trailingAnchor, constant: 10),
            permTitle.topAnchor.constraint(equalTo: permBox.topAnchor, constant: 12),
            permTitle.trailingAnchor.constraint(lessThanOrEqualTo: permBox.trailingAnchor, constant: -12),

            permLabel.leadingAnchor.constraint(equalTo: permTitle.leadingAnchor),
            permLabel.topAnchor.constraint(equalTo: permTitle.bottomAnchor, constant: 3),
            permLabel.trailingAnchor.constraint(lessThanOrEqualTo: permBox.trailingAnchor, constant: -12),
            permLabel.bottomAnchor.constraint(lessThanOrEqualTo: permBox.bottomAnchor, constant: -8),
        ])

        // 主按钮（标准系统按钮，自动跟随强调色）
        let btn = NSButton(frame: .zero)
        btn.title = "授权并开始使用"
        btn.bezelStyle = .rounded
        btn.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        btn.keyEquivalent = "\r"
        btn.target = self
        btn.action = #selector(startTapped)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.widthAnchor.constraint(equalToConstant: 240).isActive = true
        btn.heightAnchor.constraint(equalToConstant: 38).isActive = true
        column.addArrangedSubview(btn)
        self.startButton = btn
        column.setCustomSpacing(8, after: btn)

        let footnote = NSTextField(labelWithString: "授权完成后将自动继续，无需重启应用")
        footnote.font = NSFont.systemFont(ofSize: 11)
        footnote.textColor = .tertiaryLabelColor
        footnote.alignment = .center
        footnote.backgroundColor = .clear
        column.addArrangedSubview(footnote)

        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 30),
            column.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            // 小于等于：内容变长（本地化等）时约束仍可满足，不会被迫随机断链
            column.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -12),
            column.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 24),
            column.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -24),
        ])
    }

    private func makeFeatureCell(symbol: String, title: String, desc: String) -> NSView {
        let cell = AppearanceAwareView { v in
            v.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.22).cgColor
        }
        cell.translatesAutoresizingMaskIntoConstraints = false
        cell.wantsLayer = true
        cell.layer?.cornerRadius = 8
        cell.layer?.cornerCurve = .continuous

        let icon = NSImageView()
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            icon.image = img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 17, weight: .medium))
            icon.contentTintColor = .controlAccentColor
        }
        icon.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(icon)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.backgroundColor = .clear
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(titleLabel)

        let descLabel = NSTextField(labelWithString: desc)
        descLabel.font = NSFont.systemFont(ofSize: 11)
        descLabel.textColor = .secondaryLabelColor
        descLabel.backgroundColor = .clear
        descLabel.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(descLabel)

        NSLayoutConstraint.activate([
            cell.widthAnchor.constraint(equalToConstant: 252),
            cell.heightAnchor.constraint(equalToConstant: 68),

            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 16),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 24),
            icon.heightAnchor.constraint(equalToConstant: 24),

            titleLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            titleLabel.topAnchor.constraint(equalTo: cell.topAnchor, constant: 13),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -12),

            descLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            descLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            descLabel.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -12),
        ])

        return cell
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
        startButton?.isEnabled = false
        permLabel?.stringValue = "请把图标拖进系统设置的列表，授权完成后将自动继续。"
    }

    private func resetForPermissionRetry() {
        startButton?.isEnabled = true
        startButton?.title = "再次尝试授权"
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
