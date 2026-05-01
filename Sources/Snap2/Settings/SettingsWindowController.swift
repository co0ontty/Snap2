import AppKit

/// 设置窗口 — 左侧液态玻璃侧边栏 + 右侧详情。
final class SettingsWindowController: NSWindowController {

    static let shared = SettingsWindowController()

    // 详情视图缓存
    private let generalVC = SettingsViewController(settingsType: .general)
    private let hotkeyVC  = SettingsViewController(settingsType: .hotkey)
    private let aboutVC   = SettingsViewController(settingsType: .about)

    // 侧边栏
    private var sidebarStack: NSStackView!
    private var sidebarItems: [SidebarItemView] = []
    private var detailContainer: NSView!

    private enum Tab: Int, CaseIterable {
        case general, hotkey, about

        var label: String {
            switch self {
            case .general: return "通用"
            case .hotkey:  return "快捷键"
            case .about:   return "关于"
            }
        }
        var icon: String {
            switch self {
            case .general: return "gearshape.fill"
            case .hotkey:  return "keyboard"
            case .about:   return "info.circle.fill"
            }
        }
        var subtitle: String {
            switch self {
            case .general: return "保存与格式"
            case .hotkey:  return "全局快捷键"
            case .about:   return "版本与信息"
            }
        }
    }

    private var currentTab: Tab = .general

    private init() {
        let size = NSSize(width: 780, height: 500)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Snap² 设置"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.center()
        window.appearance = NSAppearance(named: .vibrantDark)

        super.init(window: window)
        buildLayout(size: size)
        select(tab: .general)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - 布局

    private func buildLayout(size: NSSize) {
        guard let contentView = window?.contentView else { return }

        // 全窗口玻璃底
        let blur = NSVisualEffectView(frame: contentView.bounds)
        blur.material = .underWindowBackground
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.autoresizingMask = [.width, .height]
        contentView.addSubview(blur)

        // 顶部高光
        let highlightHost = NSView(frame: contentView.bounds)
        highlightHost.autoresizingMask = [.width, .height]
        highlightHost.wantsLayer = true
        let highlight = CAGradientLayer()
        highlight.colors = [
            NSColor.white.withAlphaComponent(0.18).cgColor,
            NSColor.white.withAlphaComponent(0.0).cgColor,
        ]
        highlight.locations = [0.0, 1.0]
        highlight.startPoint = CGPoint(x: 0.5, y: 1.0)
        highlight.endPoint = CGPoint(x: 0.5, y: 0.55)
        highlight.frame = highlightHost.bounds
        highlightHost.layer?.addSublayer(highlight)
        contentView.addSubview(highlightHost)

        // —— 侧边栏（液态玻璃）——
        let sidebarWidth: CGFloat = 220
        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.blendingMode = .behindWindow
        sidebar.state = .active
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(sidebar)

        // 侧边栏右侧 1px 分隔线
        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
        divider.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(divider)

        // 侧边栏标题
        let brand = NSStackView()
        brand.orientation = .horizontal
        brand.spacing = 10
        brand.alignment = .centerY
        brand.translatesAutoresizingMaskIntoConstraints = false

        let brandIconBg = NSView()
        brandIconBg.wantsLayer = true
        brandIconBg.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.85).cgColor
        brandIconBg.layer?.cornerRadius = 8
        brandIconBg.layer?.borderColor = NSColor.white.withAlphaComponent(0.30).cgColor
        brandIconBg.layer?.borderWidth = 1
        brandIconBg.translatesAutoresizingMaskIntoConstraints = false
        brandIconBg.widthAnchor.constraint(equalToConstant: 30).isActive = true
        brandIconBg.heightAnchor.constraint(equalToConstant: 30).isActive = true

        let brandIcon = NSImageView()
        brandIcon.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold))
        brandIcon.contentTintColor = .white
        brandIcon.translatesAutoresizingMaskIntoConstraints = false
        brandIconBg.addSubview(brandIcon)
        NSLayoutConstraint.activate([
            brandIcon.centerXAnchor.constraint(equalTo: brandIconBg.centerXAnchor),
            brandIcon.centerYAnchor.constraint(equalTo: brandIconBg.centerYAnchor),
        ])

        let brandText = NSStackView()
        brandText.orientation = .vertical
        brandText.spacing = 0
        brandText.alignment = .leading

        let brandTitle = NSTextField(labelWithString: "Snap²")
        brandTitle.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        brandTitle.textColor = NSColor.white.withAlphaComponent(0.95)
        brandTitle.backgroundColor = .clear

        let brandSub = NSTextField(labelWithString: "截图 · 标注")
        brandSub.font = NSFont.systemFont(ofSize: 10)
        brandSub.textColor = NSColor.white.withAlphaComponent(0.55)
        brandSub.backgroundColor = .clear

        brandText.addArrangedSubview(brandTitle)
        brandText.addArrangedSubview(brandSub)

        brand.addArrangedSubview(brandIconBg)
        brand.addArrangedSubview(brandText)

        sidebar.addSubview(brand)

        // 菜单
        sidebarStack = NSStackView()
        sidebarStack.orientation = .vertical
        sidebarStack.spacing = 4
        sidebarStack.alignment = .leading
        sidebarStack.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(sidebarStack)

        for tab in Tab.allCases {
            let item = SidebarItemView(
                icon: tab.icon,
                title: tab.label,
                subtitle: tab.subtitle
            )
            item.onClick = { [weak self] in self?.select(tab: tab) }
            item.translatesAutoresizingMaskIntoConstraints = false
            item.heightAnchor.constraint(equalToConstant: 44).isActive = true
            item.widthAnchor.constraint(equalToConstant: sidebarWidth - 24).isActive = true
            sidebarStack.addArrangedSubview(item)
            sidebarItems.append(item)
        }

        // 底部版本号
        let versionLabel = NSTextField(labelWithString: "v\(appVersion())")
        versionLabel.font = NSFont.systemFont(ofSize: 10)
        versionLabel.textColor = NSColor.white.withAlphaComponent(0.40)
        versionLabel.backgroundColor = .clear
        versionLabel.alignment = .center
        versionLabel.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(versionLabel)

        // —— 详情容器 ——
        detailContainer = NSView()
        detailContainer.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(detailContainer)

        // —— 约束 ——
        NSLayoutConstraint.activate([
            sidebar.topAnchor.constraint(equalTo: contentView.topAnchor),
            sidebar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            sidebar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: sidebarWidth),

            divider.topAnchor.constraint(equalTo: contentView.topAnchor),
            divider.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            divider.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),

            // 给标题让出 titlebar 高度
            brand.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 38),
            brand.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 18),

            sidebarStack.topAnchor.constraint(equalTo: brand.bottomAnchor, constant: 22),
            sidebarStack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 12),
            sidebarStack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -12),

            versionLabel.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -14),
            versionLabel.centerXAnchor.constraint(equalTo: sidebar.centerXAnchor),

            detailContainer.topAnchor.constraint(equalTo: contentView.topAnchor),
            detailContainer.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            detailContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            detailContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    private func appVersion() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    // MARK: - 切换

    private func select(tab: Tab) {
        currentTab = tab
        for (i, item) in sidebarItems.enumerated() {
            item.setSelected(i == tab.rawValue)
        }

        let vc: NSViewController
        switch tab {
        case .general: vc = generalVC
        case .hotkey:  vc = hotkeyVC
        case .about:   vc = aboutVC
        }

        // 替换详情视图
        for sub in detailContainer.subviews { sub.removeFromSuperview() }
        let v = vc.view
        v.translatesAutoresizingMaskIntoConstraints = false
        detailContainer.addSubview(v)
        NSLayoutConstraint.activate([
            v.topAnchor.constraint(equalTo: detailContainer.topAnchor),
            v.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor),
            v.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor),
            v.bottomAnchor.constraint(equalTo: detailContainer.bottomAnchor),
        ])
    }

    // MARK: - 显示

    func showWindow() {
        guard let window = self.window else { return }
        if !window.isVisible { window.center() }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - 侧边栏单项（液态玻璃 hover/选中）

final class SidebarItemView: NSView {

    var onClick: (() -> Void)?

    private let bgLayer = CALayer()
    private let strokeLayer = CAShapeLayer()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")

    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private var isSelected = false

    init(icon: String, title: String, subtitle: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false

        bgLayer.cornerRadius = 10
        bgLayer.cornerCurve = .continuous
        layer?.addSublayer(bgLayer)

        strokeLayer.fillColor = .clear
        strokeLayer.lineWidth = 1
        strokeLayer.strokeColor = NSColor.clear.cgColor
        layer?.addSublayer(strokeLayer)

        if let img = NSImage(systemSymbolName: icon, accessibilityDescription: title) {
            iconView.image = img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .medium))
        }
        iconView.contentTintColor = NSColor.white.withAlphaComponent(0.75)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        titleLabel.stringValue = title
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = NSColor.white.withAlphaComponent(0.85)
        titleLabel.backgroundColor = .clear
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        subtitleLabel.stringValue = subtitle
        subtitleLabel.font = NSFont.systemFont(ofSize: 10)
        subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.45)
        subtitleLabel.backgroundColor = .clear
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subtitleLabel)

        let iconBg = NSView()
        iconBg.wantsLayer = true
        iconBg.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        iconBg.layer?.cornerRadius = 7
        iconBg.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconBg, positioned: .below, relativeTo: iconView)

        NSLayoutConstraint.activate([
            iconBg.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconBg.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconBg.widthAnchor.constraint(equalToConstant: 26),
            iconBg.heightAnchor.constraint(equalToConstant: 26),

            iconView.centerXAnchor.constraint(equalTo: iconBg.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconBg.centerYAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: iconBg.trailingAnchor, constant: 10),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
        ])

        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let a = trackingArea { removeTrackingArea(a) }
        let a = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(a); trackingArea = a
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true; refresh() }
    override func mouseExited(with event: NSEvent)  { isHovered = false; refresh() }
    override func mouseDown(with event: NSEvent)    { onClick?() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bgLayer.frame = bounds
        strokeLayer.frame = bounds
        let inset: CGFloat = 0.5
        let r = bounds.insetBy(dx: inset, dy: inset)
        strokeLayer.path = CGPath(roundedRect: r, cornerWidth: 10 - inset, cornerHeight: 10 - inset, transform: nil)
        CATransaction.commit()
    }

    func setSelected(_ selected: Bool) {
        isSelected = selected
        refresh()
    }

    private func refresh() {
        CATransaction.begin()
        CATransaction.setAnimationDuration(Glass.animDuration)

        if isSelected {
            bgLayer.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor
            strokeLayer.strokeColor = NSColor.white.withAlphaComponent(0.22).cgColor
            titleLabel.textColor = NSColor.white
            subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.65)
            iconView.contentTintColor = NSColor.white
        } else if isHovered {
            bgLayer.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
            strokeLayer.strokeColor = NSColor.white.withAlphaComponent(0.10).cgColor
            titleLabel.textColor = NSColor.white.withAlphaComponent(0.92)
            subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.55)
            iconView.contentTintColor = NSColor.white.withAlphaComponent(0.92)
        } else {
            bgLayer.backgroundColor = NSColor.clear.cgColor
            strokeLayer.strokeColor = NSColor.clear.cgColor
            titleLabel.textColor = NSColor.white.withAlphaComponent(0.85)
            subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.45)
            iconView.contentTintColor = NSColor.white.withAlphaComponent(0.78)
        }
        CATransaction.commit()
    }
}
