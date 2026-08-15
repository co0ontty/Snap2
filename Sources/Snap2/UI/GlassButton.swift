import AppKit

/// 玻璃按钮（扁平版）。无边框、悬停高亮、选中态纯色填充。
/// 非 final：PinHoverToolbar.ToolGlassButton 通过继承挂载 toolType 身份。
class GlassButton: NSButton {

    private let bgLayer = CALayer()
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private var isPressed = false

    var isSelected: Bool = false {
        didSet { refreshState() }
    }

    var accentColor: NSColor = .controlAccentColor {
        didSet { refreshState() }
    }

    /// 危险/警示按钮：始终显示 accentColor 染色背景（用于关闭键等）
    var isDestructive: Bool = false {
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

        layer?.insertSublayer(bgLayer, at: 0)

        if let symbol = symbol, let img = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
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

        refreshState()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        rebuildHoverTrackingArea(existing: &trackingArea)
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
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshState()
    }

    private func refreshState() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            CATransaction.begin()
            CATransaction.setAnimationDuration(Glass.animDuration)
            if isDestructive {
                // 危险按钮：常态保持低调，hover/press 才出红色高亮。
                let alpha: CGFloat = isPressed ? 0.44 : (isHovered ? 0.30 : 0.10)
                bgLayer.backgroundColor = accentColor.withAlphaComponent(alpha).cgColor
            } else if isPressed {
                bgLayer.backgroundColor = isSelected
                    ? accentColor.withAlphaComponent(0.30).cgColor
                    : Glass.pressedFill.cgColor
            } else if isSelected {
                bgLayer.backgroundColor = accentColor.withAlphaComponent(0.28).cgColor
            } else if isHovered {
                bgLayer.backgroundColor = Glass.hoverFill.cgColor
            } else {
                bgLayer.backgroundColor = NSColor.clear.cgColor
            }

            contentTintColor = (isSelected || isDestructive)
                ? .white
                : NSColor.white.withAlphaComponent(isHovered ? 1.0 : 0.86)
            CATransaction.commit()
        }
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
        ringLayer.lineWidth = 1.5
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        rebuildHoverTrackingArea(existing: &trackingArea)
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
        // 给色点描一道极轻的浅边——黑色 swatch 在深色玻璃背景上原本会"消失"，
        // 加 1px 半透白后所有颜色都看得见轮廓，不破坏整体观感。
        dotLayer.borderColor = NSColor.white.withAlphaComponent(0.30).cgColor
        dotLayer.borderWidth = 1

        // 选中态：白色外环
        let ringInset: CGFloat = 1
        let ringRect = bounds.insetBy(dx: ringInset, dy: ringInset)
        ringLayer.path = CGPath(ellipseIn: ringRect, transform: nil)
        ringLayer.frame = bounds
        ringLayer.strokeColor = isSelected
            ? NSColor.white.withAlphaComponent(0.90).cgColor
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
