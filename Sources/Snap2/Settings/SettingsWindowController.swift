import AppKit

/// 设置窗口 — 原生风：左侧系统侧边栏 + 右侧平铺详情区。
final class SettingsWindowController: NSWindowController {

    static let shared = SettingsWindowController()

    // 详情视图缓存
    private let generalVC = SettingsViewController(settingsType: .general)
    private let hotkeyVC  = SettingsViewController(settingsType: .hotkey)
    private let aboutVC   = SettingsViewController(settingsType: .about)

    // 侧边栏
    private var sidebarStack: NSStackView!
    private var sidebarItems: [SidebarItemView] = []
    private var detailColumn: NSView!
    /// 当前挂载在 detailColumn 里的滚动视图（切换时整体移除重建）
    private var detailScrollView: NSScrollView?
    /// documentView ↔ clipView 的适配约束；换页前显式 deactivate，防止换回旧页时残留死约束
    private var detailFitConstraints: [NSLayoutConstraint] = []

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
            case .general: return "gearshape"
            case .hotkey:  return "keyboard"
            case .about:   return "info.circle"
            }
        }
    }

    private var currentTab: Tab = .general

    private init() {
        // 560 → 620：通用页新增"悬停保持增强"一行（card1 变两行）后，
        // JPEG 质量行展开的最坏情况会超出旧高度，整体加高让所有分页留有余量。
        let size = NSSize(width: 860, height: 620)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Snap² 设置"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = .windowBackgroundColor
        // 内容超长时滚动（详情区套 NSScrollView），窗口可自由缩放
        window.minSize = NSSize(width: 720, height: 460)
        window.center()
        // 跟随系统明暗
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

        // —— 侧边栏（系统 sidebar 材质）——
        let sidebarWidth: CGFloat = 232
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

        // 侧边栏品牌：App 图标 + 名称
        let brand = NSStackView()
        brand.orientation = .horizontal
        brand.spacing = 8
        brand.alignment = .centerY
        brand.translatesAutoresizingMaskIntoConstraints = false

        let brandIcon = NSImageView()
        brandIcon.image = NSApplication.shared.applicationIconImage
        brandIcon.imageScaling = .scaleProportionallyUpOrDown
        brandIcon.translatesAutoresizingMaskIntoConstraints = false
        brand.addArrangedSubview(brandIcon)

        let brandTitle = NSTextField(labelWithString: "Snap²")
        brandTitle.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        brandTitle.textColor = .labelColor
        brandTitle.backgroundColor = .clear
        brand.addArrangedSubview(brandTitle)

        sidebar.addSubview(brand)

        NSLayoutConstraint.activate([
            brandIcon.widthAnchor.constraint(equalToConstant: 24),
            brandIcon.heightAnchor.constraint(equalToConstant: 24),
        ])

        // 菜单
        sidebarStack = NSStackView()
        sidebarStack.orientation = .vertical
        sidebarStack.spacing = 4
        sidebarStack.alignment = .leading
        sidebarStack.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(sidebarStack)

        for tab in Tab.allCases {
            let item = SidebarItemView(icon: tab.icon, title: tab.label)
            item.onClick = { [weak self] in self?.select(tab: tab) }
            item.translatesAutoresizingMaskIntoConstraints = false
            item.heightAnchor.constraint(equalToConstant: 34).isActive = true
            item.widthAnchor.constraint(equalToConstant: sidebarWidth - 24).isActive = true
            sidebarStack.addArrangedSubview(item)
            sidebarItems.append(item)
        }

        // 底部：可点击版本号 + 升级胶囊（默认隐藏）
        versionButton = VersionLinkButton(text: "v\(AppInfo.version)")
        versionButton.onClick = { [weak self] in self?.triggerUpdateCheck() }

        upgradePill = UpgradePillButton()
        upgradePill.isHidden = true
        upgradePill.onClick = { [weak self] in self?.triggerUpdateCheck() }

        let footer = NSStackView(views: [versionButton, upgradePill])
        footer.orientation = .horizontal
        footer.spacing = 8
        footer.alignment = .centerY
        footer.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(footer)

        // —— 详情列（贴左、限宽、可滚动）——
        // 内容列限宽与系统设置一致：行控件不贴到窗口右缘，缩放窗口时观感稳定。
        // 宽度必须"确定"：只有两个 <=（限宽 648 / 不越过窗口右缘）时解不唯一，
        // 缩放或重启都可能解出塌缩宽度（表现为内容只剩一半）。
        // 用一条 999 优先级的右缘等式把宽度尽量顶满——999 压过 scrollview 的
        // 内容拥抱（250，否则两者同为 250 会平局掷硬币），又让位于两条 1000
        // 级上限，最终宽度恒等于 min(648, 可用宽度)，数学上唯一。
        let maxColumnWidth: CGFloat = 648
        detailColumn = NSView()
        detailColumn.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(detailColumn)

        let stretchToEdge = detailColumn.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        stretchToEdge.priority = NSLayoutConstraint.Priority(999)
        NSLayoutConstraint.activate([
            detailColumn.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            detailColumn.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor),
            detailColumn.widthAnchor.constraint(lessThanOrEqualToConstant: maxColumnWidth),
            detailColumn.widthAnchor.constraint(greaterThanOrEqualToConstant: 360),
            stretchToEdge,
            detailColumn.topAnchor.constraint(equalTo: contentView.topAnchor),
            detailColumn.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

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
            brand.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 44),
            brand.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 20),

            sidebarStack.topAnchor.constraint(equalTo: brand.bottomAnchor, constant: 18),
            sidebarStack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 12),
            sidebarStack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -12),

            footer.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -14),
            footer.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 20),
        ])
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

        // 换页 = 整体摘掉旧滚动视图。
        // 旧实现摘的是 documentView.superview——那是 NSClipView（NSScrollView 的
        // 内部裁剪视图），AppKit 会抛 "removeFromSuperview called for NSScrollView
        // contentView" 异常。事件回调里该异常被 AppKit 吞掉后 select 半途中断：
        // 侧边栏高亮已切换、新内容从未挂载、旧滚动视图内部被拆坏 → 内容区空白。
        NSLayoutConstraint.deactivate(detailFitConstraints)
        detailFitConstraints = []
        detailScrollView?.removeFromSuperview()

        let v = vc.view
        v.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.verticalScrollElasticity = .none
        detailColumn.addSubview(scroll)
        scroll.documentView = v
        detailScrollView = scroll

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: detailColumn.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: detailColumn.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: detailColumn.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: detailColumn.bottomAnchor),
        ])

        // 只做纵向滚动：宽度始终撑满可视区，高度随内容自然生长
        //（macOS 无 UIScrollView 式 contentLayoutGuide，用 NSClipView 当锚点）
        let fit = [
            v.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            v.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            v.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            v.bottomAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.bottomAnchor),
        ]
        NSLayoutConstraint.activate(fit)
        detailFitConstraints = fit
    }

    // MARK: - 键盘导航

    /// ↑/↓ 在分页间循环切换，⌘1…⌘3 直达。NSWindowController 在响应链里
    /// （window 的 delegate 即本控制器），无控件捕获按键时会落到这里。
    override func keyDown(with event: NSEvent) {
        guard event.window === window else {
            super.keyDown(with: event)
            return
        }
        let tabs = Tab.allCases
        if event.modifierFlags.contains(.command),
           let digit = event.charactersIgnoringModifiers.flatMap({ Int($0) }),
           (1...tabs.count).contains(digit) {
            select(tab: tabs[digit - 1])
            return
        }
        switch event.keyCode {
        case 125: // ↓
            select(tab: tabs[(currentTab.rawValue + 1) % tabs.count])
        case 126: // ↑
            select(tab: tabs[(currentTab.rawValue - 1 + tabs.count) % tabs.count])
        default:
            super.keyDown(with: event)
        }
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
        if let latest = UpdateAvailabilityStore.cachedLatestVersionIfNewer {
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

    /// 菜单栏「关于」入口统一跳设置窗的关于页（替代系统 about 面板，避免两套信息）。
    func showAboutPage() {
        select(tab: .about)
        showWindow()
    }
}

// MARK: - 侧边栏单项（扁平：纯图标 + 文字，选中系统强调色平铺）

final class SidebarItemView: NSView {

    var onClick: (() -> Void)?

    private let bgLayer = CALayer()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")

    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private var isSelected = false
    private var keyObservers: [NSObjectProtocol] = []

    init(icon: String, title: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true

        bgLayer.cornerRadius = 6
        bgLayer.cornerCurve = .continuous
        layer?.addSublayer(bgLayer)

        if let img = NSImage(systemSymbolName: icon, accessibilityDescription: title) {
            iconView.image = img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .regular))
        }
        iconView.contentTintColor = .secondaryLabelColor
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        titleLabel.stringValue = title
        titleLabel.font = NSFont.systemFont(ofSize: 13)
        titleLabel.textColor = .labelColor
        titleLabel.backgroundColor = .clear
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
        ])

        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        rebuildHoverTrackingArea(existing: &trackingArea)
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true; refresh() }
    override func mouseExited(with event: NSEvent)  { isHovered = false; refresh() }
    override func mouseDown(with event: NSEvent)    { onClick?() }

    /// 挂进窗口后监听 key 状态：失焦时选中态降为系统 unemphasized 色（macOS 标准行为）
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        keyObservers.forEach(NotificationCenter.default.removeObserver)
        keyObservers = []
        guard let window = window else { return }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            keyObservers.append(NotificationCenter.default.addObserver(
                forName: name, object: window, queue: .main
            ) { [weak self] _ in self?.refresh() })
        }
        refresh()
    }

    deinit {
        keyObservers.forEach(NotificationCenter.default.removeObserver)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bgLayer.frame = bounds
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
                let emphasized = window?.isKeyWindow ?? true
                bgLayer.backgroundColor = (emphasized
                    ? NSColor.selectedContentBackgroundColor
                    : NSColor.unemphasizedSelectedContentBackgroundColor).cgColor
                titleLabel.textColor = emphasized ? .white : .labelColor
                iconView.contentTintColor = emphasized ? .white : .labelColor
            } else if isHovered {
                // 中性灰罩层，浅深色模式下都成立
                bgLayer.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
                titleLabel.textColor = .labelColor
                iconView.contentTintColor = .secondaryLabelColor
            } else {
                bgLayer.backgroundColor = NSColor.clear.cgColor
                titleLabel.textColor = .labelColor
                iconView.contentTintColor = .secondaryLabelColor
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
        label.font = NSFont.systemFont(ofSize: 11)
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
        rebuildHoverTrackingArea(existing: &trackingArea,
                                 options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .cursorUpdate])
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
            label.textColor = isHovered ? .labelColor : .tertiaryLabelColor
        }
    }
}

/// 升级胶囊按钮：系统强调色平铺 + 向上箭头 + "升级" 文字。
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
        // 把版本号一并显示，与菜单栏"新版本 v… 可用"的文案对齐。
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
        rebuildHoverTrackingArea(existing: &trackingArea,
                                 options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .cursorUpdate])
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
            // 扁平单色，hover 时轻微收紧透明度
            bgLayer.backgroundColor = NSColor.controlAccentColor
                .withAlphaComponent(isHovered ? 0.85 : 1.0).cgColor
        }
    }
}
