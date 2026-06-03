import AppKit
import Carbon.HIToolbox

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
    private var savePathLabel: NSTextField?
    private var formatPopup: NSPopUpButton?
    private var qualitySlider: NSSlider?
    private var qualityValueLabel: NSTextField?
    private var qualityCard: NSView?

    // 快捷键设置控件（按 Action 索引，方便重置时刷新对应行）
    private var hotkeyRecorderViews: [HotkeyManager.Action: HotkeyRecorderView] = [:]

    init(settingsType: SettingsType) {
        self.settingsType = settingsType
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 500))
        container.wantsLayer = true
        self.view = container

        // 标题
        let (header, subtitle) = headerStrings()
        let titleLabel = NSTextField(labelWithString: header)
        titleLabel.font = NSFont.systemFont(ofSize: 24, weight: .semibold)
        titleLabel.textColor = ClaudeTheme.ink
        titleLabel.backgroundColor = .clear
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleLabel)

        let subtitleLabel = NSTextField(labelWithString: subtitle)
        subtitleLabel.font = NSFont.systemFont(ofSize: 12)
        subtitleLabel.textColor = ClaudeTheme.inkSecondary
        subtitleLabel.backgroundColor = .clear
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(subtitleLabel)

        // 内容容器
        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)

        NSLayoutConstraint.activate([
            // 顶部留出 titlebar
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 38),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 32),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -32),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            content.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 22),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 30),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -30),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -24),
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

    // MARK: - 玻璃卡片容器

    private func makeCard(in parent: NSView, height: CGFloat? = nil) -> NSView {
        let card = AppearanceAwareView { v in
            v.layer?.backgroundColor = ClaudeTheme.creamCard.cgColor
            v.layer?.borderColor = ClaudeTheme.stroke.cgColor
            v.layer?.shadowColor = ClaudeTheme.accentShadow.cgColor
        }
        card.wantsLayer = true
        card.layer?.cornerRadius = 12
        card.layer?.cornerCurve = .continuous
        card.layer?.borderWidth = 1
        // 轻量阴影让卡片浮在玻璃之上
        card.layer?.shadowOpacity = 1.0
        card.layer?.shadowRadius = 10
        card.layer?.shadowOffset = CGSize(width: 0, height: -3)
        card.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(card)
        if let h = height {
            card.heightAnchor.constraint(equalToConstant: h).isActive = true
        }
        return card
    }

    private func makeRow(label: String, control: NSView, accessory: NSView? = nil) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: label)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = ClaudeTheme.ink
        titleLabel.backgroundColor = .clear
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(titleLabel)

        control.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(control)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            titleLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            control.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            control.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])
        row.heightAnchor.constraint(equalToConstant: 50).isActive = true
        return row
    }

    private func makeSeparator(in parent: NSView) -> NSView {
        let sep = AppearanceAwareDivider()
        sep.translatesAutoresizingMaskIntoConstraints = false
        sep.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return sep
    }

    // MARK: - 通用设置

    private func setupGeneralSettings(in parent: NSView) {
        let defaults = UserDefaults.standard

        // —— 卡片 1: 启动 ——
        let card1 = makeCard(in: parent)

        let toggle = NSSwitch()
        toggle.state = LaunchAtLogin.isEnabled ? .on : .off
        toggle.target = self
        toggle.action = #selector(launchAtLoginChanged(_:))
        launchAtLoginSwitch = toggle
        let row1 = makeRow(label: "开机自启动", control: toggle)
        card1.addSubview(row1)

        NSLayoutConstraint.activate([
            row1.topAnchor.constraint(equalTo: card1.topAnchor),
            row1.leadingAnchor.constraint(equalTo: card1.leadingAnchor),
            row1.trailingAnchor.constraint(equalTo: card1.trailingAnchor),
            row1.bottomAnchor.constraint(equalTo: card1.bottomAnchor),
        ])

        // —— 卡片 2: 保存与格式 ——
        let card2 = makeCard(in: parent)

        // 保存位置
        let hasCustomPath = defaults.string(forKey: UDKey.saveDirectory) != nil
        let currentPath = defaults.string(forKey: UDKey.saveDirectory)
            ?? NSSearchPathForDirectoriesInDomains(.desktopDirectory, .userDomainMask, true).first
            ?? "~/Desktop"

        // 无自定义路径时显示"~/Desktop（默认）"提示，避免用户以为已经选过桌面。
        let displayText = hasCustomPath ? abbreviatePath(currentPath)
                                        : "\(abbreviatePath(currentPath))（默认）"
        let pathLabel = NSTextField(labelWithString: displayText)
        pathLabel.font = NSFont.systemFont(ofSize: 12)
        pathLabel.textColor = ClaudeTheme.inkSecondary
        pathLabel.backgroundColor = .clear
        pathLabel.lineBreakMode = .byTruncatingMiddle
        // 完整路径作为 tooltip，让长路径用户 hover 即可看清。
        pathLabel.toolTip = currentPath
        savePathLabel = pathLabel

        let chooseBtn = NSButton(title: "选择…", target: self, action: #selector(chooseSaveDirectory(_:)))
        chooseBtn.bezelStyle = .rounded
        chooseBtn.controlSize = .small

        let pathStack = NSStackView(views: [pathLabel, chooseBtn])
        pathStack.orientation = .horizontal
        pathStack.spacing = 8
        pathStack.alignment = .centerY
        pathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        pathLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 220).isActive = true

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
        valLabel.textColor = ClaudeTheme.inkSecondary
        valLabel.backgroundColor = .clear
        valLabel.alignment = .right
        valLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true
        qualityValueLabel = valLabel

        let qualityStack = NSStackView(views: [slider, valLabel])
        qualityStack.orientation = .horizontal
        qualityStack.spacing = 10
        qualityStack.alignment = .centerY

        let row2c = makeRow(label: "JPEG 质量", control: qualityStack)
        qualityCard = row2c
        row2c.isHidden = !(savedFormat == "jpeg")

        // 回车键行为
        let enterPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        enterPopup.addItems(withTitles: ["复制到剪贴板", "保存到指定目录"])
        enterPopup.selectItem(at: EnterAction.current == .save ? 1 : 0)
        enterPopup.target = self
        enterPopup.action = #selector(enterActionChanged(_:))
        let row2d = makeRow(label: "回车键行为", control: enterPopup)

        let card2Stack = NSStackView()
        card2Stack.orientation = .vertical
        card2Stack.spacing = 0
        card2Stack.alignment = .leading
        card2Stack.translatesAutoresizingMaskIntoConstraints = false
        card2Stack.distribution = .fill
        card2.addSubview(card2Stack)

        for (i, row) in [row2a, row2b, row2c, row2d].enumerated() {
            card2Stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: card2Stack.widthAnchor).isActive = true
            if i < 3 {
                let sep = makeSeparator(in: card2Stack)
                card2Stack.addArrangedSubview(sep)
                sep.widthAnchor.constraint(equalTo: card2Stack.widthAnchor, constant: -32).isActive = true
            }
        }

        NSLayoutConstraint.activate([
            card2Stack.topAnchor.constraint(equalTo: card2.topAnchor),
            card2Stack.leadingAnchor.constraint(equalTo: card2.leadingAnchor),
            card2Stack.trailingAnchor.constraint(equalTo: card2.trailingAnchor),
            card2Stack.bottomAnchor.constraint(equalTo: card2.bottomAnchor),
        ])

        // —— 卡片 3: 更新通道 ——
        let card3 = makeCard(in: parent)

        let betaToggle = NSSwitch()
        betaToggle.state = defaults.bool(forKey: UDKey.betaUpdates) ? .on : .off
        betaToggle.target = self
        betaToggle.action = #selector(betaUpdatesChanged(_:))
        let row3 = makeRow(label: "更新 Beta 版本", control: betaToggle)
        card3.addSubview(row3)
        NSLayoutConstraint.activate([
            row3.topAnchor.constraint(equalTo: card3.topAnchor),
            row3.leadingAnchor.constraint(equalTo: card3.leadingAnchor),
            row3.trailingAnchor.constraint(equalTo: card3.trailingAnchor),
            row3.bottomAnchor.constraint(equalTo: card3.bottomAnchor),
        ])

        // —— 整体布局 ——
        let mainStack = NSStackView(views: [card1, card2, card3])
        mainStack.orientation = .vertical
        mainStack.spacing = 14
        mainStack.alignment = .leading
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: parent.topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
        ])
    }

    // MARK: - 快捷键设置

    private func setupHotkeySettings(in parent: NSView) {
        // 一个 action 一张卡：[录制新组合] + 分隔 + [恢复默认]
        let captureCard = makeHotkeyCard(action: .capture,
                                         title: "区域截图",
                                         defaultHint: "⌃⇧A")
        let recordCard = makeHotkeyCard(action: .record,
                                        title: "区域录屏",
                                        defaultHint: "⌃⇧R")

        // 提示
        let hintIcon = NSImageView()
        hintIcon.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .regular))
        hintIcon.contentTintColor = ClaudeTheme.inkTertiary
        hintIcon.translatesAutoresizingMaskIntoConstraints = false

        let hint = NSTextField(labelWithString: "点击录制框后按下新的快捷键组合，按 Esc 取消。")
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = ClaudeTheme.inkTertiary
        hint.backgroundColor = .clear

        let hintStack = NSStackView(views: [hintIcon, hint])
        hintStack.orientation = .horizontal
        hintStack.spacing = 6
        hintStack.alignment = .centerY
        hintStack.translatesAutoresizingMaskIntoConstraints = false

        // 主栈
        let mainStack = NSStackView(views: [captureCard, recordCard, hintStack])
        mainStack.orientation = .vertical
        mainStack.spacing = 14
        mainStack.alignment = .leading
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: parent.topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: parent.trailingAnchor),

            captureCard.leadingAnchor.constraint(equalTo: mainStack.leadingAnchor),
            captureCard.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor),
            recordCard.leadingAnchor.constraint(equalTo: mainStack.leadingAnchor),
            recordCard.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor),
        ])
    }

    /// 单个 action 的卡片：标题行 + 录制行 + 分隔 + 重置行。
    /// - Parameters:
    ///   - action: 要绑定的 HotkeyManager.Action
    ///   - title: 标题（"区域截图"/"区域录屏"）
    ///   - defaultHint: 重置按钮提示中显示的默认组合
    private func makeHotkeyCard(action: HotkeyManager.Action,
                                title: String,
                                defaultHint: String) -> NSView {
        // 临时挂到 self.view；后续由 mainStack.addArrangedSubview 重新 parent
        let card = makeCard(in: view)

        // 标题行（仅文字，左对齐）
        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        let head = NSTextField(labelWithString: title)
        head.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        head.textColor = ClaudeTheme.ink
        head.backgroundColor = .clear
        head.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(head)
        NSLayoutConstraint.activate([
            head.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            head.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            header.heightAnchor.constraint(equalToConstant: 38),
        ])

        // 录制行
        let recorder = HotkeyRecorderView(action: action,
                                          frame: NSRect(x: 0, y: 0, width: 240, height: 36))
        recorder.translatesAutoresizingMaskIntoConstraints = false
        recorder.widthAnchor.constraint(equalToConstant: 240).isActive = true
        recorder.heightAnchor.constraint(equalToConstant: 32).isActive = true
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
        resetBtn.controlSize = .regular
        resetBtn.tag = Int(action.rawValue)
        let resetRow = makeRow(label: "默认设置", control: resetBtn)

        let sep1 = makeSeparator(in: card)
        let sep2 = makeSeparator(in: card)

        card.addSubview(header)
        card.addSubview(sep1)
        card.addSubview(recordRow)
        card.addSubview(sep2)
        card.addSubview(resetRow)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: card.topAnchor),
            header.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: card.trailingAnchor),

            sep1.topAnchor.constraint(equalTo: header.bottomAnchor),
            sep1.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            sep1.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),

            recordRow.topAnchor.constraint(equalTo: sep1.bottomAnchor),
            recordRow.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            recordRow.trailingAnchor.constraint(equalTo: card.trailingAnchor),

            sep2.topAnchor.constraint(equalTo: recordRow.bottomAnchor),
            sep2.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            sep2.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),

            resetRow.topAnchor.constraint(equalTo: sep2.bottomAnchor),
            resetRow.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            resetRow.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            resetRow.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ])

        return card
    }

    // MARK: - 关于

    private func setupAboutSection(in parent: NSView) {
        let card = makeCard(in: parent)

        // Logo
        let logoBg = AppearanceAwareGradientView(cornerRadius: 18)
        logoBg.translatesAutoresizingMaskIntoConstraints = false

        let logoIcon = NSImageView()
        logoIcon.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 32, weight: .light))
        logoIcon.contentTintColor = .white
        logoIcon.translatesAutoresizingMaskIntoConstraints = false
        logoBg.addSubview(logoIcon)
        NSLayoutConstraint.activate([
            logoIcon.centerXAnchor.constraint(equalTo: logoBg.centerXAnchor),
            logoIcon.centerYAnchor.constraint(equalTo: logoBg.centerYAnchor),
        ])

        let appName = NSTextField(labelWithString: "Snap²")
        appName.font = NSFont.systemFont(ofSize: 22, weight: .semibold)
        appName.textColor = ClaudeTheme.ink
        appName.backgroundColor = .clear

        let appVer = NSTextField(labelWithString: "版本 \(appVersion()) (\(appBuild()))")
        appVer.font = NSFont.systemFont(ofSize: 11)
        appVer.textColor = ClaudeTheme.inkTertiary
        appVer.backgroundColor = .clear

        let desc = NSTextField(labelWithString: "轻盈快捷的 macOS 截图标注工具，纯 Swift + AppKit 构建，无外部依赖。")
        desc.font = NSFont.systemFont(ofSize: 12)
        desc.textColor = ClaudeTheme.inkSecondary
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

        card.addSubview(logoBg)
        card.addSubview(textStack)

        NSLayoutConstraint.activate([
            logoBg.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 22),
            logoBg.topAnchor.constraint(equalTo: card.topAnchor, constant: 22),
            logoBg.widthAnchor.constraint(equalToConstant: 72),
            logoBg.heightAnchor.constraint(equalToConstant: 72),

            textStack.leadingAnchor.constraint(equalTo: logoBg.trailingAnchor, constant: 18),
            textStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -22),
            textStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 22),
            textStack.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -22),

            card.bottomAnchor.constraint(greaterThanOrEqualTo: logoBg.bottomAnchor, constant: 22),
        ])

        // 信息卡
        let infoCard = makeCard(in: parent)

        let infoRows: [(String, String)] = [
            ("系统要求", "macOS 14.0+"),
            ("运行架构", Self.runtimeArchDescription),
            ("捕获引擎", "ScreenCaptureKit"),
        ]

        let infoStack = NSStackView()
        infoStack.orientation = .vertical
        infoStack.spacing = 0
        infoStack.alignment = .leading
        infoStack.translatesAutoresizingMaskIntoConstraints = false
        infoCard.addSubview(infoStack)

        for (i, item) in infoRows.enumerated() {
            let valLabel = NSTextField(labelWithString: item.1)
            valLabel.font = NSFont.systemFont(ofSize: 12)
            valLabel.textColor = ClaudeTheme.inkSecondary
            valLabel.backgroundColor = .clear

            let row = makeRow(label: item.0, control: valLabel)
            infoStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: infoStack.widthAnchor).isActive = true
            if i < infoRows.count - 1 {
                let sep = makeSeparator(in: infoStack)
                infoStack.addArrangedSubview(sep)
                sep.widthAnchor.constraint(equalTo: infoStack.widthAnchor, constant: -32).isActive = true
            }
        }

        NSLayoutConstraint.activate([
            infoStack.topAnchor.constraint(equalTo: infoCard.topAnchor),
            infoStack.leadingAnchor.constraint(equalTo: infoCard.leadingAnchor),
            infoStack.trailingAnchor.constraint(equalTo: infoCard.trailingAnchor),
            infoStack.bottomAnchor.constraint(equalTo: infoCard.bottomAnchor),
        ])

        let mainStack = NSStackView(views: [card, infoCard])
        mainStack.orientation = .vertical
        mainStack.spacing = 14
        mainStack.alignment = .leading
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: parent.topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: parent.trailingAnchor),

            card.leadingAnchor.constraint(equalTo: mainStack.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor),
            infoCard.leadingAnchor.constraint(equalTo: mainStack.leadingAnchor),
            infoCard.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor),
        ])
    }

    private func appVersion() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private func appBuild() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
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
            let path = url.path
            UserDefaults.standard.set(path, forKey: UDKey.saveDirectory)
            // 用户已选定，去掉"（默认）"后缀，同时更新 tooltip 为完整路径
            self?.savePathLabel?.stringValue = self?.abbreviatePath(path) ?? path
            self?.savePathLabel?.toolTip = path
        }
    }

    @objc private func formatChanged(_ sender: NSPopUpButton) {
        let isJPEG = sender.indexOfSelectedItem == 1
        UserDefaults.standard.set(isJPEG ? "jpeg" : "png", forKey: UDKey.imageFormat)
        qualityCard?.isHidden = !isJPEG
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

    private func abbreviatePath(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}

// MARK: - 快捷键录制视图（玻璃风格）

final class HotkeyRecorderView: NSView {

    var onHotkeyRecorded: ((UInt32, NSEvent.ModifierFlags) -> Void)?

    /// 该录制器绑定的 Action。控制 setupUI / resetDisplay 拿到的"当前键位"来源；
    /// 写入仍由外部 onHotkeyRecorded 回调决定，避免双写。
    let action: HotkeyManager.Action

    private var isRecording = false
    private var displayLabel: NSTextField!
    private var localMonitor: Any?

    init(action: HotkeyManager.Action, frame frameRect: NSRect) {
        self.action = action
        super.init(frame: frameRect)
        setupUI()
    }

    /// 兼容旧调用：默认绑定截图（capture）action。
    override convenience init(frame frameRect: NSRect) {
        self.init(action: .capture, frame: frameRect)
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
        layer?.cornerRadius = 8
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
            layer?.borderColor = ClaudeTheme.stroke.cgColor
            layer?.backgroundColor = ClaudeTheme.controlFill.cgColor
            displayLabel.textColor = ClaudeTheme.ink
        }
    }

    override func mouseDown(with event: NSEvent) {
        if isRecording { stopRecording() } else { startRecording() }
    }

    private func startRecording() {
        isRecording = true
        displayLabel.stringValue = "请按下快捷键…"
        effectiveAppearance.performAsCurrentDrawingAppearance {
            displayLabel.textColor = ClaudeTheme.accent
            layer?.borderColor = ClaudeTheme.focusRing.cgColor
            layer?.backgroundColor = ClaudeTheme.selectionFill.cgColor
        }
        layer?.borderWidth = 2

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
