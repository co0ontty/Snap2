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
    private var currentDetailView: NSView?

    // 侧边栏底部 — 可点击版本号 + 升级胶囊
    private var versionButton: VersionLinkButton!
    private var upgradePill: UpgradePillButton!

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
            // 通用页含：启动 / 保存与格式 / 更新通道，旧文案"保存与格式"误导
            case .general: return "启动、保存与更新"
            case .hotkey:  return "全局快捷键"
            case .about:   return "版本与信息"
            }
        }
    }

    private var currentTab: Tab = .general

    private init() {
        let size = NSSize(width: 860, height: 560)
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
        // 跟随系统明暗：浅色给米白纸面、深色给暖深棕
        window.appearance = nil

        super.init(window: window)
        buildLayout(size: size)
        setupUpdateObservers()
        applyInitialUpdateState()
        select(tab: .general)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - 布局

    private func buildLayout(size: NSSize) {
        guard let contentView = window?.contentView else { return }

        // 全窗口液态玻璃底（米白 tint + 顶光 + 底暖光，自动跟随系统明暗）
        ClaudeGlass.install(into: contentView)

        // —— 侧边栏（液态玻璃）——
        let sidebarWidth: CGFloat = 236
        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.blendingMode = .behindWindow
        sidebar.state = .active
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(sidebar)

        // 侧边栏右侧 1px 分隔线
        let divider = AppearanceAwareDivider()
        divider.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(divider)

        // 侧边栏标题
        let brand = NSStackView()
        brand.orientation = .horizontal
        brand.spacing = 10
        brand.alignment = .centerY
        brand.translatesAutoresizingMaskIntoConstraints = false

        let brandIconBg = AppearanceAwareView { v in
            v.layer?.backgroundColor = ClaudeTheme.accent.withAlphaComponent(0.92).cgColor
            v.layer?.borderColor = NSColor.white.withAlphaComponent(0.45).cgColor
        }
        brandIconBg.wantsLayer = true
        brandIconBg.layer?.cornerRadius = 8
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
        brandTitle.textColor = ClaudeTheme.ink
        brandTitle.backgroundColor = .clear

        let brandSub = NSTextField(labelWithString: "截图 · 标注")
        brandSub.font = NSFont.systemFont(ofSize: 10)
        brandSub.textColor = ClaudeTheme.inkSecondary
        brandSub.backgroundColor = .clear

        brandText.addArrangedSubview(brandTitle)
        brandText.addArrangedSubview(brandSub)

        brand.addArrangedSubview(brandIconBg)
        brand.addArrangedSubview(brandText)

        sidebar.addSubview(brand)

        // 菜单
        sidebarStack = NSStackView()
        sidebarStack.orientation = .vertical
        sidebarStack.spacing = 8
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
            item.heightAnchor.constraint(equalToConstant: 52).isActive = true
            item.widthAnchor.constraint(equalToConstant: sidebarWidth - 24).isActive = true
            sidebarStack.addArrangedSubview(item)
            sidebarItems.append(item)
        }

        // 底部：可点击版本号 + 升级胶囊（默认隐藏）
        versionButton = VersionLinkButton(text: "v\(appVersion())")
        versionButton.onClick = { [weak self] in self?.triggerUpdateCheck() }

        upgradePill = UpgradePillButton()
        upgradePill.isHidden = true
        upgradePill.onClick = { [weak self] in self?.triggerUpdateCheck() }

        let footer = NSStackView(views: [versionButton, upgradePill])
        footer.orientation = .horizontal
        footer.spacing = 6
        footer.alignment = .centerY
        footer.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(footer)

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
            brand.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 42),
            brand.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 20),

            sidebarStack.topAnchor.constraint(equalTo: brand.bottomAnchor, constant: 26),
            sidebarStack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 12),
            sidebarStack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -12),

            footer.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -14),
            footer.centerXAnchor.constraint(equalTo: sidebar.centerXAnchor),
            footer.leadingAnchor.constraint(greaterThanOrEqualTo: sidebar.leadingAnchor, constant: 12),
            footer.trailingAnchor.constraint(lessThanOrEqualTo: sidebar.trailingAnchor, constant: -12),

            detailContainer.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            detailContainer.leadingAnchor.constraint(equalTo: divider.trailingAnchor, constant: 14),
            detailContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            detailContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14),
        ])

        let detailPanel = AppearanceAwareView { v in
            v.layer?.backgroundColor = ClaudeTheme.cream.withAlphaComponent(0.52).cgColor
            v.layer?.borderColor = ClaudeTheme.stroke.cgColor
        }
        detailPanel.translatesAutoresizingMaskIntoConstraints = false
        detailPanel.wantsLayer = true
        detailPanel.layer?.cornerRadius = 22
        detailPanel.layer?.cornerCurve = .continuous
        detailPanel.layer?.borderWidth = 1
        detailPanel.layer?.shadowColor = ClaudeTheme.accent.withAlphaComponent(0.10).cgColor
        detailPanel.layer?.shadowOpacity = 1.0
        detailPanel.layer?.shadowRadius = 18
        detailPanel.layer?.shadowOffset = CGSize(width: 0, height: -4)
        detailContainer.addSubview(detailPanel)

        NSLayoutConstraint.activate([
            detailPanel.topAnchor.constraint(equalTo: detailContainer.topAnchor),
            detailPanel.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor),
            detailPanel.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor),
            detailPanel.bottomAnchor.constraint(equalTo: detailContainer.bottomAnchor),
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
        currentDetailView?.removeFromSuperview()
        let v = vc.view
        v.translatesAutoresizingMaskIntoConstraints = false
        detailContainer.addSubview(v)
        currentDetailView = v
        NSLayoutConstraint.activate([
            v.topAnchor.constraint(equalTo: detailContainer.topAnchor, constant: 4),
            v.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor, constant: 4),
            v.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor, constant: -4),
            v.bottomAnchor.constraint(equalTo: detailContainer.bottomAnchor, constant: -4),
        ])
    }

    // MARK: - 更新检查 UI 联动

    private func setupUpdateObservers() {
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(handleUpdateAvailable(_:)),
                       name: .updateAvailable, object: nil)
        nc.addObserver(self, selector: #selector(handleUpdateNotAvailable(_:)),
                       name: .updateNotAvailable, object: nil)
    }

    private func applyInitialUpdateState() {
        let current = UpdateChecker.shared.currentVersion
        if let latest = UserDefaults.standard.string(forKey: UDKey.lastKnownLatestVersion),
           !latest.isEmpty,
           UpdateChecker.isVersionNewer(latest, than: current) {
            upgradePill.setLatestVersion(latest)
            upgradePill.isHidden = false
        } else {
            upgradePill.isHidden = true
        }
    }

    @objc private func handleUpdateAvailable(_ note: Notification) {
        guard let outcome = note.object as? UpdateChecker.Outcome,
              case .newer(_, let latest, _, _) = outcome else { return }
        upgradePill.setLatestVersion(latest)
        upgradePill.isHidden = false
    }

    @objc private func handleUpdateNotAvailable(_ note: Notification) {
        upgradePill.isHidden = true
    }

    private func triggerUpdateCheck() {
        // 把 alert / 安装流程委托给菜单栏控制器统一处理
        NotificationCenter.default.post(name: .updateCheckRequested, object: nil)
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

        bgLayer.cornerRadius = 12
        bgLayer.cornerCurve = .continuous
        layer?.addSublayer(bgLayer)

        strokeLayer.fillColor = .clear
        strokeLayer.lineWidth = 1
        strokeLayer.strokeColor = NSColor.clear.cgColor
        layer?.addSublayer(strokeLayer)

        if let img = NSImage(systemSymbolName: icon, accessibilityDescription: title) {
            iconView.image = img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .medium))
        }
        iconView.contentTintColor = ClaudeTheme.inkSecondary
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        titleLabel.stringValue = title
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = ClaudeTheme.ink
        titleLabel.backgroundColor = .clear
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        subtitleLabel.stringValue = subtitle
        subtitleLabel.font = NSFont.systemFont(ofSize: 10)
        subtitleLabel.textColor = ClaudeTheme.inkTertiary
        subtitleLabel.backgroundColor = .clear
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subtitleLabel)

        let iconBg = AppearanceAwareView { v in
            v.layer?.backgroundColor = ClaudeTheme.creamCard.cgColor
        }
        iconBg.wantsLayer = true
        iconBg.layer?.cornerRadius = 7
        iconBg.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconBg, positioned: .below, relativeTo: iconView)

        NSLayoutConstraint.activate([
            iconBg.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconBg.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconBg.widthAnchor.constraint(equalToConstant: 28),
            iconBg.heightAnchor.constraint(equalToConstant: 28),

            iconView.centerXAnchor.constraint(equalTo: iconBg.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconBg.centerYAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: iconBg.trailingAnchor, constant: 10),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
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
        strokeLayer.path = CGPath(roundedRect: r, cornerWidth: 12 - inset, cornerHeight: 12 - inset, transform: nil)
        CATransaction.commit()
    }

    func setSelected(_ selected: Bool) {
        isSelected = selected
        refresh()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }

    private func refresh() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            CATransaction.begin()
            CATransaction.setAnimationDuration(Glass.animDuration)

            if isSelected {
                bgLayer.backgroundColor = ClaudeTheme.accent.withAlphaComponent(0.18).cgColor
                strokeLayer.strokeColor = ClaudeTheme.accent.withAlphaComponent(0.55).cgColor
                titleLabel.textColor = ClaudeTheme.ink
                subtitleLabel.textColor = ClaudeTheme.inkSecondary
                iconView.contentTintColor = ClaudeTheme.accent
            } else if isHovered {
                bgLayer.backgroundColor = ClaudeTheme.creamCardHover.cgColor
                strokeLayer.strokeColor = ClaudeTheme.stroke.cgColor
                titleLabel.textColor = ClaudeTheme.ink
                subtitleLabel.textColor = ClaudeTheme.inkSecondary
                iconView.contentTintColor = ClaudeTheme.ink
            } else {
                bgLayer.backgroundColor = ClaudeTheme.cream.withAlphaComponent(0.26).cgColor
                strokeLayer.strokeColor = NSColor.clear.cgColor
                titleLabel.textColor = ClaudeTheme.ink
                subtitleLabel.textColor = ClaudeTheme.inkTertiary
                iconView.contentTintColor = ClaudeTheme.inkSecondary
            }
            CATransaction.commit()
        }
    }
}

// MARK: - 侧边栏底部 — 版本号 / 升级胶囊

/// 版本号样式的可点击 "链接"，hover 时变亮，点击触发 onClick。
final class VersionLinkButton: NSView {

    var onClick: (() -> Void)?

    private let label = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    init(text: String) {
        super.init(frame: .zero)
        wantsLayer = true

        label.stringValue = text
        label.font = NSFont.systemFont(ofSize: 10)
        label.backgroundColor = .clear
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
        ])

        toolTip = "点击检查更新"
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setText(_ s: String) { label.stringValue = s }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let a = trackingArea { removeTrackingArea(a) }
        let a = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .cursorUpdate],
                               owner: self, userInfo: nil)
        addTrackingArea(a); trackingArea = a
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.pointingHand.set() }
    override func mouseEntered(with event: NSEvent) { isHovered = true; refresh() }
    override func mouseExited(with event: NSEvent)  { isHovered = false; refresh() }
    override func mouseDown(with event: NSEvent)    { onClick?() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }

    private func refresh() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            label.textColor = isHovered ? ClaudeTheme.ink : ClaudeTheme.inkTertiary
        }
    }
}

/// 升级胶囊按钮：accent 色背景 + 向上箭头 + "升级" 文字。
/// 仅在有新版本时由外部 setLatestVersion + 取消 isHidden 显示。
final class UpgradePillButton: NSView {

    var onClick: (() -> Void)?

    private let bgLayer = CALayer()
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "升级")
    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 60, height: 18))
        wantsLayer = true
        layer?.masksToBounds = false

        bgLayer.cornerRadius = 9
        bgLayer.cornerCurve = .continuous
        layer?.addSublayer(bgLayer)

        let cfg = NSImage.SymbolConfiguration(pointSize: 9, weight: .bold)
        iconView.image = NSImage(systemSymbolName: "arrow.up.circle.fill",
                                 accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg)
        iconView.contentTintColor = .white
        iconView.translatesAutoresizingMaskIntoConstraints = false

        label.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .white
        label.backgroundColor = .clear
        label.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [iconView, label])
        stack.orientation = .horizontal
        stack.spacing = 3
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            heightAnchor.constraint(equalToConstant: 18),
        ])

        toolTip = "发现新版本，点击立即升级"
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setLatestVersion(_ v: String) {
        // 旧实现只更新 tooltip，按钮文本永远是"升级"——必须 hover 才看得到版本号。
        // 改为把版本号一并显示，与菜单栏"新版本 v… 可用"的文案对齐。
        label.stringValue = "升级 v\(v)"
        label.sizeToFit()
        invalidateIntrinsicContentSize()
        needsLayout = true
        toolTip = "新版本 v\(v) 可用，点击升级"
    }

    override var intrinsicContentSize: NSSize {
        // 自适应文字宽度：基础 16px padding + label 自身宽度 + icon + 间距
        let textWidth = label.intrinsicContentSize.width
        return NSSize(width: max(60, textWidth + 36), height: 18)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bgLayer.frame = bounds
        CATransaction.commit()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let a = trackingArea { removeTrackingArea(a) }
        let a = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .cursorUpdate],
                               owner: self, userInfo: nil)
        addTrackingArea(a); trackingArea = a
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.pointingHand.set() }
    override func mouseEntered(with event: NSEvent) { isHovered = true; refresh() }
    override func mouseExited(with event: NSEvent)  { isHovered = false; refresh() }
    override func mouseDown(with event: NSEvent)    { onClick?() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }

    private func refresh() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            bgLayer.backgroundColor = (isHovered ? ClaudeTheme.accentPressed : ClaudeTheme.accent).cgColor
        }
    }
}
