import AppKit
import Carbon.HIToolbox
import CoreGraphics

enum SettingsType {
    case general
    case hotkey
    case about
}

// MARK: - 设置详情视图

final class SettingsViewController: NSViewController {

    /// 当前进程架构的可读描述（编译期决定，universal 二进制下随实际加载架构呈现）
    static let runtimeArchDescription: String = {
        #if arch(arm64)
        return "Apple Silicon · arm64"
        #elseif arch(x86_64)
        return "Intel · x86_64"
        #else
        return "未知架构"
        #endif
    }()

    private let settingsType: SettingsType

    // 通用设置控件
    private var launchAtLoginSwitch: NSSwitch?
    private var savePathControl: NSPathControl?
    private var formatPopup: NSPopUpButton?
    private var qualitySlider: NSSlider?
    private var qualityValueLabel: NSTextField?
    private var qualityRow: NSView?
    private var hoverEnhanceStatusLabel: NSTextField?
    private var hoverEnhanceButton: NSButton?

    // 快捷键设置控件（按 Action 索引，方便重置时刷新对应行）
    private var hotkeyRecorderViews: [HotkeyManager.Action: HotkeyRecorderView] = [:]

    init(settingsType: SettingsType) {
        self.settingsType = settingsType
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 540))
        container.wantsLayer = true
        self.view = container

        // 标题
        let (header, subtitle) = headerStrings()
        let titleLabel = NSTextField(labelWithString: header)
        titleLabel.font = Layout.titleFont
        titleLabel.textColor = .labelColor
        titleLabel.backgroundColor = .clear
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleLabel)

        let subtitleLabel = NSTextField(labelWithString: subtitle)
        subtitleLabel.font = Layout.subtitleFont
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.backgroundColor = .clear
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(subtitleLabel)

        // 内容容器
        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 36),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Layout.contentInset),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Layout.contentInset),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            content.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 24),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Layout.contentInset),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Layout.contentInset),
            // 高度由内容驱动（配合外层 NSScrollView 滚动），不再依赖固定窗口高度
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Layout.contentInset),
        ])

        switch settingsType {
        case .general: setupGeneralSettings(in: content)
        case .hotkey:  setupHotkeySettings(in: content)
        case .about:   setupAboutSection(in: content)
        }
    }

    private func headerStrings() -> (String, String) {
        switch settingsType {
        case .general: return ("通用", "管理保存位置、文件格式与默认行为")
        case .hotkey:  return ("快捷键", "自定义触发区域截图的全局快捷键")
        case .about:   return ("关于 Snap²", "应用信息与项目说明")
        }
    }

    // MARK: - 分区列表容器（扁平：分区标题 + 行 + 细分隔线）

    /// 新建一个分区。返回纵向栈，行之间用 1px hairline 分隔。
    private func makeSection(title: String, in parent: NSView) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .leading
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = Layout.sectionFont
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.backgroundColor = .clear
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(titleLabel)
        stack.setCustomSpacing(4, after: titleLabel)

        parent.addSubview(stack)
        return stack
    }

    private func makeRow(label: String, control: NSView) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: label)
        titleLabel.font = Layout.rowFont
        titleLabel.textColor = .labelColor
        titleLabel.backgroundColor = .clear
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(titleLabel)

        control.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(control)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            control.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            control.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])
        row.heightAnchor.constraint(equalToConstant: Layout.rowHeight).isActive = true
        return row
    }

    /// 把若干行装进分区栈。
    /// 分隔线是每一行自己的底部子视图（最后一行除外），随行整体隐藏——
    /// 「JPEG 质量」行在 PNG 格式下隐藏时，不会残留悬空分隔线或空隙。
    private func addRows(_ rows: [NSView], to stack: NSStackView) {
        for (i, row) in rows.enumerated() {
            if i < rows.count - 1 {
                attachSeparator(to: row)
            }
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    private func attachSeparator(to row: NSView) {
        let sep = AppearanceAwareDivider()
        sep.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(sep)
        NSLayoutConstraint.activate([
            sep.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            sep.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            sep.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    // MARK: - 通用设置

    private func setupGeneralSettings(in parent: NSView) {
        let defaults = UserDefaults.standard

        // —— 分区 1: 启动 ——
        let section1 = makeSection(title: "启动", in: parent)

        let toggle = NSSwitch()
        toggle.state = LaunchAtLogin.isEnabled ? .on : .off
        toggle.target = self
        toggle.action = #selector(launchAtLoginChanged(_:))
        launchAtLoginSwitch = toggle
        let row1 = makeRow(label: "开机自启动", control: toggle)
        addRows([row1], to: section1)

        // —— 分区 2: 截图 ——
        let section2 = makeSection(title: "截图", in: parent)

        // 保存位置：原生 NSPathControl 展示 + 选择按钮
        let currentPath = defaults.string(forKey: UDKey.saveDirectory)
            ?? NSSearchPathForDirectoriesInDomains(.desktopDirectory, .userDomainMask, true).first
            ?? "~/Desktop"

        let pathControl = NSPathControl()
        pathControl.controlSize = .small
        pathControl.pathStyle = .standard
        pathControl.url = URL(fileURLWithPath: currentPath)
        // 完整路径作为 tooltip，让长路径用户 hover 即可看清。
        pathControl.toolTip = currentPath
        savePathControl = pathControl

        let chooseBtn = NSButton(title: "选择…", target: self, action: #selector(chooseSaveDirectory(_:)))
        chooseBtn.bezelStyle = .rounded
        chooseBtn.controlSize = .small

        let pathStack = NSStackView(views: [pathControl, chooseBtn])
        pathStack.orientation = .horizontal
        pathStack.spacing = 8
        pathStack.alignment = .centerY
        pathControl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        pathControl.widthAnchor.constraint(lessThanOrEqualToConstant: 260).isActive = true

        let row2a = makeRow(label: "保存位置", control: pathStack)

        // 图片格式
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: ["PNG", "JPEG"])
        let savedFormat = defaults.string(forKey: UDKey.imageFormat) ?? "png"
        popup.selectItem(at: savedFormat == "jpeg" ? 1 : 0)
        popup.target = self
        popup.action = #selector(formatChanged(_:))
        popup.controlSize = .regular
        formatPopup = popup
        let row2b = makeRow(label: "图片格式", control: popup)

        // JPEG 质量
        let savedQuality = defaults.object(forKey: UDKey.jpegQuality) != nil
            ? defaults.double(forKey: UDKey.jpegQuality) : 0.85

        let slider = NSSlider(value: savedQuality, minValue: 0.1, maxValue: 1.0,
                              target: self, action: #selector(qualitySliderChanged(_:)))
        slider.controlSize = .small
        slider.widthAnchor.constraint(equalToConstant: 140).isActive = true
        qualitySlider = slider

        let valLabel = NSTextField(labelWithString: "\(Int(savedQuality * 100))%")
        valLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        valLabel.textColor = .secondaryLabelColor
        valLabel.backgroundColor = .clear
        valLabel.alignment = .right
        valLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true
        qualityValueLabel = valLabel

        let qualityStack = NSStackView(views: [slider, valLabel])
        qualityStack.orientation = .horizontal
        qualityStack.spacing = 10
        qualityStack.alignment = .centerY

        let row2c = makeRow(label: "JPEG 质量", control: qualityStack)
        qualityRow = row2c
        row2c.isHidden = !(savedFormat == "jpeg")

        // 回车键行为
        let enterPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        enterPopup.addItems(withTitles: ["复制到剪贴板", "保存到指定目录"])
        enterPopup.selectItem(at: EnterAction.current == .save ? 1 : 0)
        enterPopup.target = self
        enterPopup.action = #selector(enterActionChanged(_:))
        let row2d = makeRow(label: "回车键行为", control: enterPopup)

        addRows([row2a, row2b, row2c, row2d], to: section2)

        // —— 分区 3: 高级 ——
        let section3 = makeSection(title: "高级", in: parent)

        let betaToggle = NSSwitch()
        betaToggle.state = defaults.bool(forKey: UDKey.betaUpdates) ? .on : .off
        betaToggle.target = self
        betaToggle.action = #selector(betaUpdatesChanged(_:))
        let row3 = makeRow(label: "更新 Beta 版本", control: betaToggle)

        // —— 悬停保持增强（归入高级分区）——
        // 授权辅助功能（或输入监控）后，CaptureManager 的修饰键预冻结监听才能收到
        // 其它 app 的 flagsChanged——按下快捷键那一刻仍悬停着的 tooltip / hover 卡片
        // 会被"抢跑冻结"完整保留进截图。未授权时核心截图功能不受影响，只是抢跑不生效。
        let hoverStatus = NSTextField(labelWithString: Self.isHoverEnhanceAvailable ? "已启用" : "未启用")
        hoverStatus.font = NSFont.systemFont(ofSize: 12)
        hoverStatus.textColor = .secondaryLabelColor
        hoverStatus.backgroundColor = .clear
        hoverEnhanceStatusLabel = hoverStatus

        let authorizeBtn = NSButton(title: "去授权…", target: self,
                                    action: #selector(authorizeHoverEnhance(_:)))
        authorizeBtn.bezelStyle = .rounded
        authorizeBtn.controlSize = .small
        authorizeBtn.isHidden = Self.isHoverEnhanceAvailable
        hoverEnhanceButton = authorizeBtn

        let hoverStack = NSStackView(views: [hoverStatus, authorizeBtn])
        hoverStack.orientation = .horizontal
        hoverStack.spacing = 10
        hoverStack.alignment = .centerY

        let row1b = makeRow(label: "悬停保持增强", control: hoverStack)

        addRows([row3, row1b], to: section3)

        // —— 整体布局 ——
        let mainStack = NSStackView(views: [section1, section2, section3])
        mainStack.orientation = .vertical
        mainStack.spacing = Layout.sectionGap
        mainStack.alignment = .leading
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: parent.topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            mainStack.bottomAnchor.constraint(equalTo: parent.bottomAnchor),

            section1.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            section2.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            section3.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
        ])
    }

    // MARK: - 快捷键设置

    private func setupHotkeySettings(in parent: NSView) {
        // 一个 action 一个分区：录制行 + 分隔 + 恢复默认行
        let captureSection = makeHotkeySection(action: .capture,
                                                title: "区域截图",
                                                defaultHint: "⌃⇧A")
        let recordSection = makeHotkeySection(action: .record,
                                               title: "区域录屏",
                                               defaultHint: "⌃⇧R")

        // 提示
        let hintIcon = NSImageView()
        hintIcon.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .regular))
        hintIcon.contentTintColor = .tertiaryLabelColor
        hintIcon.translatesAutoresizingMaskIntoConstraints = false

        let hint = NSTextField(labelWithString: "点击录制框后按下新的快捷键组合，按 Esc 取消。")
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor
        hint.backgroundColor = .clear

        let hintStack = NSStackView(views: [hintIcon, hint])
        hintStack.orientation = .horizontal
        hintStack.spacing = 6
        hintStack.alignment = .centerY
        hintStack.translatesAutoresizingMaskIntoConstraints = false

        // 主栈
        let mainStack = NSStackView(views: [captureSection, recordSection, hintStack])
        mainStack.orientation = .vertical
        mainStack.spacing = Layout.sectionGap
        mainStack.alignment = .leading
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: parent.topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            mainStack.bottomAnchor.constraint(equalTo: parent.bottomAnchor),

            captureSection.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            recordSection.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
        ])
    }

    /// 单个 action 的分区：录制行 + 分隔 + 重置行。
    /// - Parameters:
    ///   - action: 要绑定的 HotkeyManager.Action
    ///   - title: 分区标题（"区域截图"/"区域录屏"）
    ///   - defaultHint: 重置按钮提示中显示的默认组合
    private func makeHotkeySection(action: HotkeyManager.Action,
                                   title: String,
                                   defaultHint: String) -> NSView {
        // 临时挂到 self.view；后续由 mainStack.addArrangedSubview 重新 parent
        let section = makeSection(title: title, in: view)

        // 录制行（尺寸由下方约束决定）
        let recorder = HotkeyRecorderView(action: action)
        recorder.translatesAutoresizingMaskIntoConstraints = false
        recorder.widthAnchor.constraint(equalToConstant: 220).isActive = true
        recorder.heightAnchor.constraint(equalToConstant: 30).isActive = true
        recorder.onHotkeyRecorded = { [weak self] keyCode, modifiers in
            self?.hotkeyDidRecord(action: action, keyCode: keyCode, modifiers: modifiers)
        }
        hotkeyRecorderViews[action] = recorder
        let recordRow = makeRow(label: "录制新组合", control: recorder)

        // 重置行
        let resetBtn = NSButton(title: "恢复默认 (\(defaultHint))",
                                target: self,
                                action: #selector(resetHotkeyTapped(_:)))
        resetBtn.bezelStyle = .rounded
        resetBtn.controlSize = .small
        resetBtn.tag = Int(action.rawValue)
        let resetRow = makeRow(label: "默认设置", control: resetBtn)

        addRows([recordRow, resetRow], to: section)

        return section
    }

    // MARK: - 关于

    private func setupAboutSection(in parent: NSView) {
        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(header)

        let logo = NSImageView()
        logo.image = NSApplication.shared.applicationIconImage
        logo.imageScaling = .scaleProportionallyUpOrDown
        logo.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(logo)

        let appName = NSTextField(labelWithString: "Snap²")
        appName.font = NSFont.systemFont(ofSize: 20, weight: .semibold)
        appName.textColor = .labelColor
        appName.backgroundColor = .clear

        let appVer = NSTextField(labelWithString: "版本 \(AppInfo.version) (\(AppInfo.build))")
        appVer.font = NSFont.systemFont(ofSize: 11)
        appVer.textColor = .tertiaryLabelColor
        appVer.backgroundColor = .clear

        let desc = NSTextField(labelWithString: "轻盈快捷的 macOS 截图标注工具，纯 Swift + AppKit 构建，无外部依赖。")
        desc.font = NSFont.systemFont(ofSize: 12)
        desc.textColor = .secondaryLabelColor
        desc.backgroundColor = .clear
        desc.maximumNumberOfLines = 0
        desc.lineBreakMode = .byWordWrapping
        desc.preferredMaxLayoutWidth = 360

        let textStack = NSStackView(views: [appName, appVer, desc])
        textStack.orientation = .vertical
        textStack.spacing = 4
        textStack.alignment = .leading
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.setCustomSpacing(10, after: appVer)

        header.addSubview(textStack)

        NSLayoutConstraint.activate([
            logo.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            logo.topAnchor.constraint(equalTo: header.topAnchor),
            logo.widthAnchor.constraint(equalToConstant: 64),
            logo.heightAnchor.constraint(equalToConstant: 64),

            textStack.leadingAnchor.constraint(equalTo: logo.trailingAnchor, constant: 16),
            textStack.centerYAnchor.constraint(equalTo: logo.centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: header.trailingAnchor),

            header.bottomAnchor.constraint(greaterThanOrEqualTo: logo.bottomAnchor),
        ])

        // 信息分区
        let infoSection = makeSection(title: "信息", in: parent)

        let infoRows: [(String, String)] = [
            ("系统要求", "macOS 14.0+"),
            ("运行架构", Self.runtimeArchDescription),
            ("捕获引擎", "ScreenCaptureKit"),
        ]

        let rowViews = infoRows.map { item in
            let valLabel = NSTextField(labelWithString: item.1)
            valLabel.font = NSFont.systemFont(ofSize: 12)
            valLabel.textColor = .secondaryLabelColor
            valLabel.backgroundColor = .clear
            return makeRow(label: item.0, control: valLabel)
        }
        addRows(rowViews, to: infoSection)

        let mainStack = NSStackView(views: [header, infoSection])
        mainStack.orientation = .vertical
        mainStack.spacing = Layout.sectionGap
        mainStack.alignment = .leading
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: parent.topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            mainStack.bottomAnchor.constraint(equalTo: parent.bottomAnchor),

            header.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            infoSection.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
        ])
    }

    // MARK: - 事件处理

    @objc private func launchAtLoginChanged(_ sender: NSSwitch) {
        let enabled = sender.state == .on
        if enabled { LaunchAtLogin.enable() } else { LaunchAtLogin.disable() }
        UserDefaults.standard.set(enabled, forKey: UDKey.launchAtLogin)
    }

    @objc private func chooseSaveDirectory(_ sender: NSButton) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        panel.message = "选择截图保存位置"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            UserDefaults.standard.set(url.path, forKey: UDKey.saveDirectory)
            self?.savePathControl?.url = url
            self?.savePathControl?.toolTip = url.path
        }
    }

    @objc private func formatChanged(_ sender: NSPopUpButton) {
        let isJPEG = sender.indexOfSelectedItem == 1
        UserDefaults.standard.set(isJPEG ? "jpeg" : "png", forKey: UDKey.imageFormat)
        qualityRow?.isHidden = !isJPEG
    }

    @objc private func qualitySliderChanged(_ sender: NSSlider) {
        let quality = sender.doubleValue
        UserDefaults.standard.set(quality, forKey: UDKey.jpegQuality)
        qualityValueLabel?.stringValue = "\(Int(quality * 100))%"
    }

    @objc private func enterActionChanged(_ sender: NSPopUpButton) {
        let action: EnterAction = sender.indexOfSelectedItem == 1 ? .save : .copy
        UserDefaults.standard.set(action.rawValue, forKey: UDKey.enterAction)
    }

    @objc private func betaUpdatesChanged(_ sender: NSSwitch) {
        let enabled = sender.state == .on
        UserDefaults.standard.set(enabled, forKey: UDKey.betaUpdates)
        NotificationCenter.default.post(name: .betaChannelChanged, object: nil)
        // 通道变化后立刻按新通道拉一次：覆盖菜单栏角标 / 设置窗口"升级"胶囊的旧缓存
        UpdateChecker.shared.invalidateCacheForChannelChange()
        UpdateChecker.shared.checkManually { _ in
            // alert 流程交给菜单栏控制器（监听 .updateAvailable）；此处只触发拉取
        }
    }

    // MARK: - 悬停保持增强

    /// 辅助功能或输入监控任一被信任，全局 flagsChanged 监听（预冻结抢跑）即可工作。
    private static var isHoverEnhanceAvailable: Bool {
        AXIsProcessTrusted() || CGPreflightListenEventAccess()
    }

    @objc private func authorizeHoverEnhance(_ sender: NSButton) {
        // from 传 nil 直接淡入（与 ensureScreenCapturePermission 的引导一致）
        PermissionAssistant.shared.present(
            panel: .accessibility,
            from: nil,
            onGranted: { [weak self] in
                self?.refreshHoverEnhanceRow()
            },
            onCancel: nil
        )
    }

    private func refreshHoverEnhanceRow() {
        let available = Self.isHoverEnhanceAvailable
        hoverEnhanceStatusLabel?.stringValue = available ? "已启用" : "未启用"
        hoverEnhanceButton?.isHidden = available
    }

    private func hotkeyDidRecord(action: HotkeyManager.Action,
                                 keyCode: UInt32,
                                 modifiers: NSEvent.ModifierFlags) {
        let carbonMods = HotkeyManager.carbonModifiers(from: modifiers)
        let result = HotkeyManager.shared.updateHotkey(action,
                                                       keyCode: keyCode,
                                                       modifiers: carbonMods)
        switch result {
        case .success:
            break
        case .failure(let err):
            switch err {
            case .conflict(let occupiedBy):
                let occupiedName = HotkeyManager.displayName(for: occupiedBy)
                // 把录制框的显示回滚为当前真实热键，并闪红提示
                hotkeyRecorderViews[action]?.resetDisplay()
                hotkeyRecorderViews[action]?.flashConflict(
                    message: "该组合已被「\(occupiedName)」占用"
                )
            }
        }
    }

    @objc private func resetHotkeyTapped(_ sender: NSButton) {
        guard let action = HotkeyManager.Action(rawValue: UInt32(sender.tag)) else { return }
        let result = HotkeyManager.shared.resetToDefault(action)
        switch result {
        case .success:
            hotkeyRecorderViews[action]?.resetDisplay()
        case .failure(.conflict(let occupiedBy)):
            // 极少见：用户把另一个 action 改成了"我的默认值"。提示而不静默重置失败。
            let name = HotkeyManager.displayName(for: occupiedBy)
            hotkeyRecorderViews[action]?.flashConflict(
                message: "默认组合已被「\(name)」占用"
            )
        }
    }

}

// MARK: - 快捷键录制视图（扁平系统风）

final class HotkeyRecorderView: NSView {

    var onHotkeyRecorded: ((UInt32, NSEvent.ModifierFlags) -> Void)?

    /// 该录制器绑定的 Action。控制 setupUI / resetDisplay 拿到的"当前键位"来源；
    /// 写入仍由外部 onHotkeyRecorded 回调决定，避免双写。
    let action: HotkeyManager.Action

    private var isRecording = false
    private var displayLabel: NSTextField!
    private var localMonitor: Any?

    init(action: HotkeyManager.Action) {
        self.action = action
        super.init(frame: .zero)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func setupUI() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1

        let manager = HotkeyManager.shared
        let currentDisplay = KeyCodeMapping.displayString(
            keyCode: manager.keyCode(for: action),
            carbonModifiers: manager.modifiers(for: action))

        displayLabel = NSTextField(labelWithString: currentDisplay)
        displayLabel.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
        displayLabel.backgroundColor = .clear
        displayLabel.alignment = .center
        displayLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(displayLabel)

        NSLayoutConstraint.activate([
            displayLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            displayLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        applyIdleStyle()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        if !isRecording { applyIdleStyle() }
    }

    private func applyIdleStyle() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderColor = NSColor.separatorColor.cgColor
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            displayLabel.textColor = .labelColor
        }
    }

    override func mouseDown(with event: NSEvent) {
        if isRecording { stopRecording() } else { startRecording() }
    }

    private func startRecording() {
        isRecording = true
        displayLabel.stringValue = "请按下快捷键…"
        effectiveAppearance.performAsCurrentDrawingAppearance {
            displayLabel.textColor = .controlAccentColor
            layer?.borderColor = NSColor.controlAccentColor.cgColor
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
        }
        layer?.borderWidth = 1.5

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        layer?.borderWidth = 1
        applyIdleStyle()

        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        if event.keyCode == kVK_Escape {
            stopRecording()
            let manager = HotkeyManager.shared
            displayLabel.stringValue = KeyCodeMapping.displayString(
                keyCode: manager.keyCode(for: action),
                carbonModifiers: manager.modifiers(for: action))
            return
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasModifier = modifiers.contains(.command) || modifiers.contains(.control) ||
                          modifiers.contains(.option) || modifiers.contains(.shift)

        let keyCode = UInt32(event.keyCode)
        // 允许无修饰键的"功能键类"快捷键（F1–F19、媒体键等），它们是合法全局热键。
        // 普通字母数字 / 符号等仍要求至少一个修饰键，避免误录"按字母 a 就触发截图"。
        if !hasModifier {
            guard Self.isFunctionKey(keyCode: keyCode) else { return }
        }

        let clean = modifiers.intersection([.command, .control, .option, .shift])
        displayLabel.stringValue = KeyCodeMapping.displayString(keyCode: keyCode, modifiers: clean)
        stopRecording()
        onHotkeyRecorded?(keyCode, clean)
    }

    /// 是否属于"无需修饰键也允许"的功能键范畴
    private static func isFunctionKey(keyCode: UInt32) -> Bool {
        // kVK_F* 在 Carbon 头里是 C int，Swift 映射成 Int；直接用 Int 数组避免逐个转。
        let fKeys: [Int] = [
            kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6,
            kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12,
            kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19,
        ]
        return fKeys.contains(Int(keyCode))
    }

    func resetDisplay() {
        let manager = HotkeyManager.shared
        displayLabel.stringValue = KeyCodeMapping.displayString(
            keyCode: manager.keyCode(for: action),
            carbonModifiers: manager.modifiers(for: action))
    }

    /// 冲突反馈：录制框红边 + 临时文案 + 自动复位为当前真实热键。
    func flashConflict(message: String) {
        let originalText = displayLabel.stringValue
        displayLabel.stringValue = message
        displayLabel.textColor = .systemRed
        layer?.borderColor = NSColor.systemRed.cgColor
        layer?.borderWidth = 2
        layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.10).cgColor

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            guard let self = self else { return }
            self.displayLabel.stringValue = originalText
            self.layer?.borderWidth = 1
            self.applyIdleStyle()
        }
    }

    override var acceptsFirstResponder: Bool { true }
}
