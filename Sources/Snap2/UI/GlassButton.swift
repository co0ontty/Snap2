import AppKit

/// 玻璃按钮。无边框、悬停高亮、选中态高亮 + 强调描边。
final class GlassButton: NSButton {

    private let bgLayer = CALayer()
    private let strokeLayer = CAShapeLayer()
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private var isPressed = false

    var isSelected: Bool = false {
        didSet { refreshState() }
    }

    var accentColor: NSColor = .controlAccentColor {
        didSet { refreshState() }
    }

    /// 选中时整个按钮的描边发光（false 时只换底色，无描边）
    var selectionGlows: Bool = true {
        didSet { refreshState() }
    }

    init(symbol: String? = nil, title: String = "", size: CGFloat = Glass.buttonSize, tooltip: String? = nil) {
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        setup(symbol: symbol, title: title, size: size, tooltip: tooltip)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup(symbol: nil, title: title, size: bounds.height, tooltip: nil)
    }

    private func setup(symbol: String?, title: String, size: CGFloat, tooltip: String?) {
        bezelStyle = .inline
        isBordered = false
        wantsLayer = true
        layer?.masksToBounds = false

        // 子层级：底色 + 描边
        layer?.insertSublayer(bgLayer, at: 0)
        layer?.addSublayer(strokeLayer)

        if let symbol = symbol, let img = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            image = img.withSymbolConfiguration(cfg)
            imagePosition = .imageOnly
            self.title = ""
        } else {
            self.title = title
            font = NSFont.systemFont(ofSize: 12, weight: .medium)
        }
        contentTintColor = NSColor.white.withAlphaComponent(0.92)

        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: size).isActive = true
        heightAnchor.constraint(equalToConstant: size).isActive = true

        if let tooltip = tooltip { self.toolTip = tooltip }

        bgLayer.cornerRadius = Glass.radiusButton
        bgLayer.cornerCurve = .continuous

        strokeLayer.fillColor = .clear
        strokeLayer.lineWidth = 1
        strokeLayer.strokeColor = NSColor.clear.cgColor

        refreshState()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = trackingArea { removeTrackingArea(area) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        refreshState()
    }
    override func mouseExited(with event: NSEvent) {
        isHovered = false
        isPressed = false
        refreshState()
    }
    override func mouseDown(with event: NSEvent) {
        isPressed = true
        refreshState()
        super.mouseDown(with: event)
        isPressed = false
        refreshState()
    }

    override func layout() {
        super.layout()
        let r = bounds.insetBy(dx: 2, dy: 2)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bgLayer.frame = r
        let strokeInset: CGFloat = 0.5
        let strokeRect = r.insetBy(dx: strokeInset, dy: strokeInset)
        strokeLayer.path = CGPath(roundedRect: strokeRect,
                                  cornerWidth: Glass.radiusButton - strokeInset,
                                  cornerHeight: Glass.radiusButton - strokeInset,
                                  transform: nil)
        strokeLayer.frame = bounds
        CATransaction.commit()
    }

    private func refreshState() {
        CATransaction.begin()
        CATransaction.setAnimationDuration(Glass.animDuration)
        if isPressed {
            bgLayer.backgroundColor = Glass.pressedFill.cgColor
        } else if isSelected {
            bgLayer.backgroundColor = Glass.selectedFill.cgColor
        } else if isHovered {
            bgLayer.backgroundColor = Glass.hoverFill.cgColor
        } else {
            bgLayer.backgroundColor = NSColor.clear.cgColor
        }

        strokeLayer.strokeColor = (isSelected && selectionGlows)
            ? accentColor.withAlphaComponent(0.85).cgColor
            : NSColor.clear.cgColor
        contentTintColor = isSelected
            ? .white
            : NSColor.white.withAlphaComponent(isHovered ? 1.0 : 0.85)
        CATransaction.commit()
    }
}

/// 圆形颜色色板按钮
final class GlassColorSwatch: NSButton {

    private let dotLayer = CALayer()
    private let ringLayer = CAShapeLayer()
    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    let color: NSColor
    var isSelected: Bool = false {
        didSet { refresh() }
    }

    init(color: NSColor, diameter: CGFloat = 22) {
        self.color = color
        super.init(frame: NSRect(x: 0, y: 0, width: diameter, height: diameter))
        bezelStyle = .inline
        isBordered = false
        title = ""
        wantsLayer = true
        layer?.masksToBounds = false

        layer?.addSublayer(dotLayer)
        layer?.addSublayer(ringLayer)

        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: diameter).isActive = true
        heightAnchor.constraint(equalToConstant: diameter).isActive = true

        ringLayer.fillColor = .clear
        ringLayer.lineWidth = 2
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let a = trackingArea { removeTrackingArea(a) }
        let a = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(a)
        trackingArea = a
    }
    override func mouseEntered(with event: NSEvent) { isHovered = true; refresh() }
    override func mouseExited(with event: NSEvent)  { isHovered = false; refresh() }

    override func layout() {
        super.layout()
        // 主色点缩进让选中态环可以画在外侧
        let dotInset: CGFloat = isSelected ? 4 : (isHovered ? 3 : 2)
        let dotRect = bounds.insetBy(dx: dotInset, dy: dotInset)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dotLayer.frame = dotRect
        dotLayer.cornerRadius = dotRect.width / 2
        dotLayer.backgroundColor = color.cgColor

        // 选中态：白色外环
        let ringInset: CGFloat = 1
        let ringRect = bounds.insetBy(dx: ringInset, dy: ringInset)
        ringLayer.path = CGPath(ellipseIn: ringRect, transform: nil)
        ringLayer.frame = bounds
        ringLayer.strokeColor = isSelected
            ? NSColor.white.withAlphaComponent(0.95).cgColor
            : NSColor.clear.cgColor
        CATransaction.commit()
    }

    private func refresh() {
        CATransaction.begin()
        CATransaction.setAnimationDuration(Glass.animDuration)
        needsLayout = true
        CATransaction.commit()
    }
}
