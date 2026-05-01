import AppKit

protocol GlassToolbarDelegate: AnyObject {
    func toolbarDidPickTool(_ tool: AnnotationToolType)
    func toolbarDidPickColor(_ color: NSColor)
    func toolbarDidPickWidth(_ width: CGFloat)
    func toolbarDidTapUndo()
    func toolbarDidTapSave()
    func toolbarDidTapCopy()
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

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        buildLayout()
    }
    required init?(coder: NSCoder) { fatalError() }

    func setSelectedTool(_ tool: AnnotationToolType) { selectedTool = tool }
    func setSelectedColor(_ color: NSColor) {
        selectedColor = color
        syncColorHighlight()
    }
    func setSelectedWidth(_ w: LineWidthLevel) { selectedWidth = w }

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
        ]
        for (sym, tip, sel) in actions {
            let b = GlassButton(symbol: sym, size: Glass.buttonSize, tooltip: tip)
            b.target = self
            b.action = sel
            stack.addArrangedSubview(b)
        }

        // 关闭按钮单独样式（红 tint）
        let closeBtn = GlassButton(symbol: "xmark", size: Glass.buttonSize, tooltip: "关闭 (Esc)")
        closeBtn.accentColor = .systemRed
        closeBtn.target = self
        closeBtn.action = #selector(closeTapped)
        stack.addArrangedSubview(closeBtn)

        syncToolHighlight()
        syncColorHighlight()
        syncWidthHighlight()
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

    @objc private func undoTapped()  { delegate?.toolbarDidTapUndo() }
    @objc private func saveTapped()  { delegate?.toolbarDidTapSave() }
    @objc private func copyTapped()  { delegate?.toolbarDidTapCopy() }
    @objc private func closeTapped() { delegate?.toolbarDidTapClose() }

    /// 计算工具栏天然宽度（外部决定面板尺寸）
    func intrinsicWidth() -> CGFloat {
        let toolsW = CGFloat(AnnotationToolType.allCases.count) * Glass.buttonSize
        let colorsW = CGFloat(AnnotationPalette.colors.count) * 22
        let widthsW = CGFloat(LineWidthLevel.allCases.count) * 26
        let actionsW = 4 * Glass.buttonSize
        let separators: CGFloat = 4 * 1
        let spacings: CGFloat = Glass.groupSpacing * CGFloat(
            AnnotationToolType.allCases.count + AnnotationPalette.colors.count
            + LineWidthLevel.allCases.count + 4 + 4 - 1
        )
        let pad = Self.toolbarPadding * 2
        return toolsW + colorsW + widthsW + actionsW + separators + spacings + pad
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
        CATransaction.begin()
        CATransaction.setAnimationDuration(Glass.animDuration)
        bgLayer.backgroundColor = isSelected ? Glass.selectedFill.cgColor
            : (isHovered ? Glass.hoverFill.cgColor : NSColor.clear.cgColor)
        dotLayer.backgroundColor = NSColor.white.withAlphaComponent(isSelected ? 1.0 : 0.85).cgColor
        CATransaction.commit()
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
