import AppKit
import Carbon.HIToolbox

enum SettingsType {
    case general
    case hotkey
    case about
}

// MARK: - 设置详情视图

final class SettingsViewController: NSViewController {

    private let settingsType: SettingsType

    // 通用设置控件
    private var launchAtLoginSwitch: NSSwitch?
    private var savePathLabel: NSTextField?
    private var formatPopup: NSPopUpButton?
    private var qualitySlider: NSSlider?
    private var qualityValueLabel: NSTextField?
    private var qualityCard: NSView?

    // 快捷键设置控件
    private var hotkeyRecorderView: HotkeyRecorderView?
    private var hotkeyDisplayLabel: NSTextField?

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
        titleLabel.font = NSFont.systemFont(ofSize: 22, weight: .semibold)
        titleLabel.textColor = NSColor.white.withAlphaComponent(0.95)
        titleLabel.backgroundColor = .clear
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleLabel)

        let subtitleLabel = NSTextField(labelWithString: subtitle)
        subtitleLabel.font = NSFont.systemFont(ofSize: 12)
        subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.55)
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

            content.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 24),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 28),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -28),
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
        let card = NSView()
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
        card.layer?.cornerRadius = 14
        card.layer?.cornerCurve = .continuous
        card.layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        card.layer?.borderWidth = 1
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
        titleLabel.textColor = NSColor.white.withAlphaComponent(0.88)
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
        row.heightAnchor.constraint(equalToConstant: 48).isActive = true
        return row
    }

    private func makeSeparator(in parent: NSView) -> NSView {
        let sep = NSView()
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
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
        let currentPath = defaults.string(forKey: UDKey.saveDirectory)
            ?? NSSearchPathForDirectoriesInDomains(.desktopDirectory, .userDomainMask, true).first
            ?? "~/Desktop"

        let pathLabel = NSTextField(labelWithString: abbreviatePath(currentPath))
        pathLabel.font = NSFont.systemFont(ofSize: 12)
        pathLabel.textColor = NSColor.white.withAlphaComponent(0.55)
        pathLabel.backgroundColor = .clear
        pathLabel.lineBreakMode = .byTruncatingMiddle
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
        valLabel.textColor = NSColor.white.withAlphaComponent(0.65)
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

        // —— 整体布局 ——
        let mainStack = NSStackView(views: [card1, card2])
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
        let manager = HotkeyManager.shared
        let currentDisplay = KeyCodeMapping.displayString(
            keyCode: manager.currentKeyCode,
            carbonModifiers: manager.currentModifiers
        )

        // 大显示卡
        let displayCard = makeCard(in: parent, height: 110)

        let bigDisplay = NSTextField(labelWithString: currentDisplay)
        bigDisplay.font = NSFont.monospacedSystemFont(ofSize: 28, weight: .medium)
        bigDisplay.textColor = NSColor.white
        bigDisplay.backgroundColor = .clear
        bigDisplay.alignment = .center
        bigDisplay.translatesAutoresizingMaskIntoConstraints = false
        hotkeyDisplayLabel = bigDisplay

        let displayHint = NSTextField(labelWithString: "当前快捷键")
        displayHint.font = NSFont.systemFont(ofSize: 11)
        displayHint.textColor = NSColor.white.withAlphaComponent(0.50)
        displayHint.backgroundColor = .clear
        displayHint.alignment = .center
        displayHint.translatesAutoresizingMaskIntoConstraints = false

        displayCard.addSubview(displayHint)
        displayCard.addSubview(bigDisplay)

        NSLayoutConstraint.activate([
            displayHint.topAnchor.constraint(equalTo: displayCard.topAnchor, constant: 18),
            displayHint.centerXAnchor.constraint(equalTo: displayCard.centerXAnchor),
            bigDisplay.topAnchor.constraint(equalTo: displayHint.bottomAnchor, constant: 6),
            bigDisplay.centerXAnchor.constraint(equalTo: displayCard.centerXAnchor),
        ])

        // 录制 + 重置卡
        let recordCard = makeCard(in: parent)

        let recorder = HotkeyRecorderView(frame: NSRect(x: 0, y: 0, width: 240, height: 36))
        recorder.translatesAutoresizingMaskIntoConstraints = false
        recorder.widthAnchor.constraint(equalToConstant: 240).isActive = true
        recorder.heightAnchor.constraint(equalToConstant: 32).isActive = true
        recorder.onHotkeyRecorded = { [weak self] keyCode, modifiers in
            self?.hotkeyDidRecord(keyCode: keyCode, modifiers: modifiers)
        }
        hotkeyRecorderView = recorder

        let recordRow = makeRow(label: "录制新组合", control: recorder)
        recordCard.addSubview(recordRow)

        let sep = makeSeparator(in: recordCard)
        recordCard.addSubview(sep)

        let resetBtn = NSButton(title: "恢复默认 (⌃⇧A)", target: self, action: #selector(resetHotkeyToDefault(_:)))
        resetBtn.bezelStyle = .rounded
        resetBtn.controlSize = .regular
        let resetRow = makeRow(label: "默认设置", control: resetBtn)
        recordCard.addSubview(resetRow)

        NSLayoutConstraint.activate([
            recordRow.topAnchor.constraint(equalTo: recordCard.topAnchor),
            recordRow.leadingAnchor.constraint(equalTo: recordCard.leadingAnchor),
            recordRow.trailingAnchor.constraint(equalTo: recordCard.trailingAnchor),

            sep.topAnchor.constraint(equalTo: recordRow.bottomAnchor),
            sep.leadingAnchor.constraint(equalTo: recordCard.leadingAnchor, constant: 16),
            sep.trailingAnchor.constraint(equalTo: recordCard.trailingAnchor, constant: -16),

            resetRow.topAnchor.constraint(equalTo: sep.bottomAnchor),
            resetRow.leadingAnchor.constraint(equalTo: recordCard.leadingAnchor),
            resetRow.trailingAnchor.constraint(equalTo: recordCard.trailingAnchor),
            resetRow.bottomAnchor.constraint(equalTo: recordCard.bottomAnchor),
        ])

        // 提示
        let hintIcon = NSImageView()
        hintIcon.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .regular))
        hintIcon.contentTintColor = NSColor.white.withAlphaComponent(0.45)
        hintIcon.translatesAutoresizingMaskIntoConstraints = false

        let hint = NSTextField(labelWithString: "点击录制框后按下新的快捷键组合，按 Esc 取消。")
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = NSColor.white.withAlphaComponent(0.50)
        hint.backgroundColor = .clear

        let hintStack = NSStackView(views: [hintIcon, hint])
        hintStack.orientation = .horizontal
        hintStack.spacing = 6
        hintStack.alignment = .centerY
        hintStack.translatesAutoresizingMaskIntoConstraints = false

        // 主栈
        let mainStack = NSStackView(views: [displayCard, recordCard, hintStack])
        mainStack.orientation = .vertical
        mainStack.spacing = 14
        mainStack.alignment = .leading
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: parent.topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: parent.trailingAnchor),

            displayCard.leadingAnchor.constraint(equalTo: mainStack.leadingAnchor),
            displayCard.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor),
            recordCard.leadingAnchor.constraint(equalTo: mainStack.leadingAnchor),
            recordCard.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor),
        ])
    }

    // MARK: - 关于

    private func setupAboutSection(in parent: NSView) {
        let card = makeCard(in: parent)

        // Logo
        let logoBg = NSView()
        logoBg.wantsLayer = true
        logoBg.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.85).cgColor
        logoBg.layer?.cornerRadius = 18
        logoBg.layer?.borderColor = NSColor.white.withAlphaComponent(0.30).cgColor
        logoBg.layer?.borderWidth = 1
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
        appName.textColor = NSColor.white.withAlphaComponent(0.95)
        appName.backgroundColor = .clear

        let appVer = NSTextField(labelWithString: "版本 \(appVersion()) (\(appBuild()))")
        appVer.font = NSFont.systemFont(ofSize: 11)
        appVer.textColor = NSColor.white.withAlphaComponent(0.55)
        appVer.backgroundColor = .clear

        let desc = NSTextField(labelWithString: "轻盈快捷的 macOS 截图标注工具，纯 Swift + AppKit 构建，无外部依赖。")
        desc.font = NSFont.systemFont(ofSize: 12)
        desc.textColor = NSColor.white.withAlphaComponent(0.70)
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
            ("运行架构", "Apple Silicon · arm64"),
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
            valLabel.textColor = NSColor.white.withAlphaComponent(0.65)
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
            self?.savePathLabel?.stringValue = self?.abbreviatePath(path) ?? path
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

    private func hotkeyDidRecord(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) {
        let carbonMods = HotkeyManager.carbonModifiers(from: modifiers)
        HotkeyManager.shared.updateHotkey(keyCode: keyCode, modifiers: carbonMods)
        let display = KeyCodeMapping.displayString(keyCode: keyCode, modifiers: modifiers)
        hotkeyDisplayLabel?.stringValue = display
    }

    @objc private func resetHotkeyToDefault(_ sender: NSButton) {
        HotkeyManager.shared.resetToDefault()
        let manager = HotkeyManager.shared
        hotkeyDisplayLabel?.stringValue = KeyCodeMapping.displayString(
            keyCode: manager.currentKeyCode, carbonModifiers: manager.currentModifiers)
        hotkeyRecorderView?.resetDisplay()
    }

    private func abbreviatePath(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}

// MARK: - 快捷键录制视图（玻璃风格）

final class HotkeyRecorderView: NSView {

    var onHotkeyRecorded: ((UInt32, NSEvent.ModifierFlags) -> Void)?

    private var isRecording = false
    private var displayLabel: NSTextField!
    private var localMonitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
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
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor

        let manager = HotkeyManager.shared
        let currentDisplay = KeyCodeMapping.displayString(
            keyCode: manager.currentKeyCode, carbonModifiers: manager.currentModifiers)

        displayLabel = NSTextField(labelWithString: currentDisplay)
        displayLabel.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
        displayLabel.textColor = NSColor.white.withAlphaComponent(0.90)
        displayLabel.backgroundColor = .clear
        displayLabel.alignment = .center
        displayLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(displayLabel)

        NSLayoutConstraint.activate([
            displayLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            displayLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    override func mouseDown(with event: NSEvent) {
        if isRecording { stopRecording() } else { startRecording() }
    }

    private func startRecording() {
        isRecording = true
        displayLabel.stringValue = "请按下快捷键…"
        displayLabel.textColor = NSColor.controlAccentColor
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        layer?.borderWidth = 2
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        displayLabel.textColor = NSColor.white.withAlphaComponent(0.90)
        layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        layer?.borderWidth = 1
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor

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
                keyCode: manager.currentKeyCode, carbonModifiers: manager.currentModifiers)
            return
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasModifier = modifiers.contains(.command) || modifiers.contains(.control) ||
                          modifiers.contains(.option) || modifiers.contains(.shift)
        guard hasModifier else { return }

        let keyCode = UInt32(event.keyCode)
        let clean = modifiers.intersection([.command, .control, .option, .shift])
        displayLabel.stringValue = KeyCodeMapping.displayString(keyCode: keyCode, modifiers: clean)
        stopRecording()
        onHotkeyRecorded?(keyCode, clean)
    }

    func resetDisplay() {
        let manager = HotkeyManager.shared
        displayLabel.stringValue = KeyCodeMapping.displayString(
            keyCode: manager.currentKeyCode, carbonModifiers: manager.currentModifiers)
    }

    override var acceptsFirstResponder: Bool { true }
}
