import AppKit

protocol GlassToolbarDelegate: AnyObject {
    func toolbarDidPickTool(_ tool: AnnotationToolType)
    func toolbarDidPickColor(_ color: NSColor)
    func toolbarDidPickWidth(_ width: CGFloat)
    func toolbarDidTapUndo()
    func toolbarDidTapSave()
    func toolbarDidTapCopy()
    func toolbarDidTapPin()
    func toolbarDidTapRecord()
    func toolbarDidTapClose()
}

/// 标注模式的玻璃工具栏。挂在 GlassPanel 中。
final class GlassToolbar: NSView {

    weak var delegate: GlassToolbarDelegate?

    private var toolButtons: [AnnotationToolType: GlassButton] = [:]
    private var colorButtons: [GlassColorSwatch] = []
    private var widthButtons: [LineWidthLevel: WidthDot] = [:]

    private(set) var selectedTool: AnnotationToolType = .arrow {
        didSet { syncToolHighlight() }
    }
    private(set) var selectedColor: NSColor = AnnotationPalette.colors[0] {
        didSet { syncColorHighlight() }
    }
    private(set) var selectedWidth: LineWidthLevel = .medium {
        didSet { syncWidthHighlight() }
    }

    static let toolbarHeight: CGFloat = 46
    static let toolbarPadding: CGFloat = 10

    /// 操作组按钮数（撤销/保存/复制/钉/录制）；不含独立的关闭按钮。
    /// intrinsicWidth 与 buildLayout 都用同一个常量，避免硬编码漂移。
    private static let actionsCount: Int = 5

    // 鼠标进入/离开整体工具栏时通知（外部用来做面板的折叠/展开）
    var onHoverEnter: (() -> Void)?
    var onHoverExit: (() -> Void)?
    private var hoverArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        buildLayout()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let a = hoverArea { removeTrackingArea(a) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHoverEnter?()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHoverExit?()
    }

    func setSelectedTool(_ tool: AnnotationToolType) {
        selectedTool = tool
        // mosaic 不消费 color，给颜色组整体 dim + 改 tooltip 提示用户
        applyMosaicModeIfNeeded()
    }
    func setSelectedColor(_ color: NSColor) {
        selectedColor = color
        syncColorHighlight()
    }
    func setSelectedWidth(_ w: LineWidthLevel) { selectedWidth = w }

    /// 根据当前工具切换颜色组的视觉态：mosaic 时整组 dim 到 0.35
    /// 并把 tooltip 改为"马赛克不使用颜色"，避免用户先选色再画 mosaic 却色不生效。
    private func applyMosaicModeIfNeeded() {
        let isMosaic = (selectedTool == .mosaic)
        for sw in colorButtons {
            sw.alphaValue = isMosaic ? 0.35 : 1.0
            sw.toolTip = isMosaic ? "马赛克不使用颜色" : nil
        }
    }

    private func buildLayout() {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = Glass.groupSpacing
        stack.edgeInsets = NSEdgeInsets(top: 0,
                                        left: Self.toolbarPadding,
                                        bottom: 0,
                                        right: Self.toolbarPadding)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        // 1. 工具组
        for tool in AnnotationToolType.allCases {
            let btn = GlassButton(symbol: tool.symbolName,
                                  size: Glass.buttonSize,
                                  tooltip: "\(tool.displayName) (\(tool.shortcutDigit))")
            btn.target = self
            btn.action = #selector(toolTapped(_:))
            btn.identifier = NSUserInterfaceItemIdentifier(rawValue: "tool.\(tool.rawValue)")
            toolButtons[tool] = btn
            stack.addArrangedSubview(btn)
        }
        stack.addArrangedSubview(separator())

        // 2. 颜色组
        for color in AnnotationPalette.colors {
            let sw = GlassColorSwatch(color: color, diameter: 22)
            sw.target = self
            sw.action = #selector(colorTapped(_:))
            colorButtons.append(sw)
            stack.addArrangedSubview(sw)
        }
        stack.addArrangedSubview(separator())

        // 3. 线宽组
        for level in LineWidthLevel.allCases {
            let dot = WidthDot(level: level)
            dot.target = self
            dot.action = #selector(widthTapped(_:))
            widthButtons[level] = dot
            stack.addArrangedSubview(dot)
        }
        stack.addArrangedSubview(separator())

        // 4. 操作组
        let actions: [(String, String, Selector)] = [
            ("arrow.uturn.backward", "撤销 (⌘Z)", #selector(undoTapped)),
            ("square.and.arrow.down", "保存 (⌘S)", #selector(saveTapped)),
            ("doc.on.clipboard", "复制 (↩)", #selector(copyTapped)),
            ("pin.fill", "钉在桌面 (⌘P)", #selector(pinTapped)),
            ("record.circle", "录制选区", #selector(recordTapped)),
        ]
        for (sym, tip, sel) in actions {
            let b = GlassButton(symbol: sym, size: Glass.buttonSize, tooltip: tip)
            b.target = self
            b.action = sel
            stack.addArrangedSubview(b)
        }

        // 关闭按钮单独样式（红 tint，始终染色）
        let closeBtn = GlassButton(symbol: "xmark", size: Glass.buttonSize, tooltip: "关闭 (Esc)")
        closeBtn.accentColor = .systemRed
        closeBtn.isDestructive = true
        closeBtn.target = self
        closeBtn.action = #selector(closeTapped)
        stack.addArrangedSubview(closeBtn)

        syncToolHighlight()
        syncColorHighlight()
        syncWidthHighlight()
        applyMosaicModeIfNeeded()
    }

    private func separator() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.white.withAlphaComponent(Glass.separatorAlpha).cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        v.widthAnchor.constraint(equalToConstant: 1).isActive = true
        v.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return v
    }

    private func syncToolHighlight() {
        for (tool, btn) in toolButtons {
            btn.isSelected = (tool == selectedTool)
        }
    }
    private func syncColorHighlight() {
        for sw in colorButtons {
            sw.isSelected = sw.color.isEqualSrgb(selectedColor)
        }
    }
    private func syncWidthHighlight() {
        for (level, dot) in widthButtons {
            dot.isSelected = (level == selectedWidth)
        }
    }

    // MARK: - Actions

    @objc private func toolTapped(_ sender: GlassButton) {
        guard let id = sender.identifier?.rawValue.split(separator: ".").last,
              let raw = Int(id),
              let tool = AnnotationToolType(rawValue: raw) else { return }
        selectedTool = tool
        delegate?.toolbarDidPickTool(tool)
    }

    @objc private func colorTapped(_ sender: GlassColorSwatch) {
        selectedColor = sender.color
        delegate?.toolbarDidPickColor(sender.color)
    }

    @objc private func widthTapped(_ sender: WidthDot) {
        selectedWidth = sender.level
        delegate?.toolbarDidPickWidth(sender.level.rawValue)
    }

    // 操作类按钮异步派发：避免在 NSButton mouseDown tracking loop 内拆掉父面板，
    // 导致后续状态更新落到已 orderOut 的窗口、动作"无反应"。
    @objc private func undoTapped()   { dispatchAction { $0.toolbarDidTapUndo() } }
    @objc private func saveTapped()   { dispatchAction { $0.toolbarDidTapSave() } }
    @objc private func copyTapped()   { dispatchAction { $0.toolbarDidTapCopy() } }
    @objc private func pinTapped()    { dispatchAction { $0.toolbarDidTapPin() } }
    @objc private func recordTapped() { dispatchAction { $0.toolbarDidTapRecord() } }
    @objc private func closeTapped()  { dispatchAction { $0.toolbarDidTapClose() } }

    private func dispatchAction(_ block: @escaping (GlassToolbarDelegate) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let d = self?.delegate else { return }
            block(d)
        }
    }

    /// 计算工具栏天然宽度（外部决定面板尺寸）
    func intrinsicWidth() -> CGFloat {
        let toolsCount = AnnotationToolType.allCases.count
        let colorsCount = AnnotationPalette.colors.count
        let widthsCount = LineWidthLevel.allCases.count
        // 操作按钮数 = actions 数组 + 1 个独立 close
        let buttonsAfterWidth = Self.actionsCount + 1
        let separatorsCount = 3 // 工具｜颜色｜线宽｜操作

        let toolsW = CGFloat(toolsCount) * Glass.buttonSize
        let colorsW = CGFloat(colorsCount) * 22
        let widthsW = CGFloat(widthsCount) * 26
        let actionsW = CGFloat(buttonsAfterWidth) * Glass.buttonSize
        let separatorsW = CGFloat(separatorsCount) * 1

        // stack 子视图总数 - 1 = spacing 数
        let totalItems = toolsCount + colorsCount + widthsCount + buttonsAfterWidth + separatorsCount
        let spacingsW = Glass.groupSpacing * CGFloat(max(0, totalItems - 1))

        let pad = Self.toolbarPadding * 2
        return toolsW + colorsW + widthsW + actionsW + separatorsW + spacingsW + pad
    }
}

// MARK: - 线宽点视图

final class WidthDot: NSButton {
    let level: LineWidthLevel
    private let dotLayer = CALayer()
    private let bgLayer = CALayer()
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    var isSelected = false { didSet { refresh() } }

    init(level: LineWidthLevel) {
        self.level = level
        super.init(frame: NSRect(x: 0, y: 0, width: 26, height: Glass.buttonSize))
        bezelStyle = .inline
        isBordered = false
        title = ""
        wantsLayer = true
        layer?.addSublayer(bgLayer)
        layer?.addSublayer(dotLayer)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 26).isActive = true
        heightAnchor.constraint(equalToConstant: Glass.buttonSize).isActive = true
        bgLayer.cornerRadius = Glass.radiusButton
        bgLayer.cornerCurve = .continuous
        toolTip = "线宽 \(level.label)"
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
    override func mouseExited(with event: NSEvent)  { isHovered = false; refresh() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }

    override func layout() {
        super.layout()
        let bg = bounds.insetBy(dx: 2, dy: 2)
        let s = level.dotSize
        let dot = NSRect(x: (bounds.width - s) / 2,
                         y: (bounds.height - s) / 2,
                         width: s, height: s)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bgLayer.frame = bg
        dotLayer.frame = dot
        dotLayer.cornerRadius = s / 2
        CATransaction.commit()
    }

    private func refresh() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            CATransaction.begin()
            CATransaction.setAnimationDuration(Glass.animDuration)
            bgLayer.backgroundColor = isSelected ? ClaudeTheme.accent.withAlphaComponent(0.22).cgColor
                : (isHovered ? Glass.hoverFill.cgColor : NSColor.clear.cgColor)
            dotLayer.backgroundColor = NSColor.white.withAlphaComponent(isSelected ? 1.0 : 0.85).cgColor
            CATransaction.commit()
        }
    }
}

// MARK: - NSColor 比较扩展

extension NSColor {
    /// 在 sRGB 空间下比较颜色（避免不同色彩空间相同色的不等）
    func isEqualSrgb(_ other: NSColor) -> Bool {
        guard let a = usingColorSpace(.sRGB), let b = other.usingColorSpace(.sRGB) else {
            return self == other
        }
        return abs(a.redComponent - b.redComponent) < 0.001
            && abs(a.greenComponent - b.greenComponent) < 0.001
            && abs(a.blueComponent - b.blueComponent) < 0.001
    }
}
