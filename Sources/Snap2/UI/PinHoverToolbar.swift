import AppKit

/// 钉图底边下方的隐藏工具栏。
/// 常态完全藏在钉图背后；鼠标悬停钉图时向下滑出，离开钉图和工具栏后收回。
final class PinHoverToolbar {

    private weak var owner: PinnedImageWindow?
    private let panel: GlassPanel
    private let toolbarView: PinHoverToolbarView

    private var isPointerInPin = false
    private var isPointerInToolbar = false
    private var isShown = false
    private var hideWorkItem: DispatchWorkItem?

    init(owner: PinnedImageWindow) {
        self.owner = owner

        let size = NSSize(width: PinHoverToolbarView.intrinsicWidth,
                          height: PinHoverToolbarView.toolbarHeight)
        self.panel = GlassPanel(size: size,
                                cornerRadius: 14,
                                level: owner.level)
        self.toolbarView = PinHoverToolbarView(frame: NSRect(origin: .zero, size: size))

        panel.alphaValue = 0
        panel.ignoresMouseEvents = true

        toolbarView.translatesAutoresizingMaskIntoConstraints = false
        panel.contentBox.addSubview(toolbarView)
        NSLayoutConstraint.activate([
            toolbarView.topAnchor.constraint(equalTo: panel.contentBox.topAnchor),
            toolbarView.bottomAnchor.constraint(equalTo: panel.contentBox.bottomAnchor),
            toolbarView.leadingAnchor.constraint(equalTo: panel.contentBox.leadingAnchor),
            toolbarView.trailingAnchor.constraint(equalTo: panel.contentBox.trailingAnchor),
        ])

        toolbarView.onHoverEnter = { [weak self] in self?.toolbarMouseEntered() }
        toolbarView.onHoverExit = { [weak self] in self?.toolbarMouseExited() }
        toolbarView.onEdit = { [weak self] in self?.owner?.editFromHoverToolbar() }
        toolbarView.onClose = { [weak self] in self?.owner?.closeFromHoverToolbar() }

        owner.addChildWindow(panel, ordered: .below)
        moveToHiddenPosition()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(ownerWindowDidMove(_:)),
            name: NSWindow.didMoveNotification,
            object: owner
        )
    }

    deinit {
        hideWorkItem?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    func pinMouseEntered() {
        isPointerInPin = true
        cancelScheduledHide()
        show()
    }

    func pinMouseExited() {
        isPointerInPin = false
        scheduleHideIfNeeded()
    }

    func hideImmediately() {
        cancelScheduledHide()
        isPointerInPin = false
        isPointerInToolbar = false
        hide(animated: false)
    }

    func detach() {
        cancelScheduledHide()
        isShown = false
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        NotificationCenter.default.removeObserver(self)
    }

    private func toolbarMouseEntered() {
        isPointerInToolbar = true
        cancelScheduledHide()
        show()
    }

    private func toolbarMouseExited() {
        isPointerInToolbar = false
        scheduleHideIfNeeded()
    }

    private func scheduleHideIfNeeded() {
        cancelScheduledHide()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            guard !self.isPointerInPin, !self.isPointerInToolbar else { return }
            self.hide(animated: true)
        }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: item)
    }

    private func cancelScheduledHide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
    }

    private func show() {
        guard let owner = owner else { return }
        attachBelowOwnerIfNeeded(owner)

        let hidden = hiddenOrigin()
        let shown = shownOrigin()
        if !isShown {
            panel.setFrameOrigin(hidden)
            panel.alphaValue = 0
        }
        isShown = true
        panel.ignoresMouseEvents = false

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.20
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            panel.animator().alphaValue = 1.0
            panel.animator().setFrameOrigin(shown)
        }
    }

    private func hide(animated: Bool) {
        let hidden = hiddenOrigin()
        isShown = false

        guard animated else {
            panel.alphaValue = 0
            panel.setFrameOrigin(hidden)
            panel.ignoresMouseEvents = true
            return
        }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.2, 1.0)
            panel.animator().alphaValue = 0
            panel.animator().setFrameOrigin(hidden)
        }, completionHandler: { [weak self] in
            guard let self = self, !self.isShown else { return }
            self.panel.ignoresMouseEvents = true
        })
    }

    private func moveToHiddenPosition() {
        panel.setFrameOrigin(hiddenOrigin())
    }

    private func attachBelowOwnerIfNeeded(_ owner: PinnedImageWindow) {
        if panel.parent !== owner {
            owner.addChildWindow(panel, ordered: .below)
        }
        if owner.windowNumber > 0 {
            panel.order(.below, relativeTo: owner.windowNumber)
        }
    }

    @objc private func ownerWindowDidMove(_ notification: Notification) {
        if isShown {
            panel.setFrameOrigin(shownOrigin())
        } else {
            moveToHiddenPosition()
        }
    }

    private func hiddenOrigin() -> NSPoint {
        guard let owner = owner else { return .zero }
        return NSPoint(x: targetX(), y: owner.frame.minY)
    }

    private func shownOrigin() -> NSPoint {
        guard let owner = owner else { return .zero }
        return NSPoint(x: targetX(), y: owner.frame.minY - panel.frame.height)
    }

    private func targetX() -> CGFloat {
        guard let owner = owner else { return 0 }
        let width = panel.frame.width
        let screenFrame = owner.screen?.visibleFrame
            ?? owner.screen?.frame
            ?? NSScreen.main?.visibleFrame
            ?? owner.frame
        let edgeMargin: CGFloat = 8
        var x = owner.frame.midX - width / 2
        let minX = screenFrame.minX + edgeMargin
        let maxX = screenFrame.maxX - width - edgeMargin
        if maxX >= minX {
            x = max(minX, min(x, maxX))
        }
        return x
    }
}

private final class PinHoverToolbarView: NSView {

    static let toolbarHeight: CGFloat = 42
    static let intrinsicWidth: CGFloat = {
        let toolsCount = CGFloat(toolbarTools.count)
        let arrangedItems = toolsCount + 4 // grip + 两条分割线 + close
        let spacings = max(0, arrangedItems - 1) * Glass.groupSpacing
        return 16 + 22 + 1 + toolsCount * buttonSize + 1 + buttonSize + spacings
    }()

    private static let buttonSize: CGFloat = 28
    private static let toolbarTools: [AnnotationToolType] = [.arrow, .rectangle, .freedraw, .text]

    var onHoverEnter: (() -> Void)?
    var onHoverExit: (() -> Void)?
    var onEdit: (() -> Void)?
    var onClose: (() -> Void)?

    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        buildLayout()
    }

    required init?(coder: NSCoder) { fatalError() }

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
        super.mouseEntered(with: event)
        onHoverEnter?()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHoverExit?()
    }

    private func buildLayout() {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = Glass.groupSpacing
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        let grip = PinToolbarGripView()
        stack.addArrangedSubview(grip)
        stack.addArrangedSubview(separator())

        for tool in Self.toolbarTools {
            let button = GlassButton(symbol: tool.symbolName,
                                     size: Self.buttonSize,
                                     tooltip: "重新标注：\(tool.displayName)")
            button.target = self
            button.action = #selector(editTapped)
            stack.addArrangedSubview(button)
        }

        stack.addArrangedSubview(separator())

        let close = GlassButton(symbol: "xmark",
                                size: Self.buttonSize,
                                tooltip: "关闭钉图")
        close.accentColor = .systemRed
        close.isDestructive = true
        close.target = self
        close.action = #selector(closeTapped)
        stack.addArrangedSubview(close)
    }

    private func separator() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.white.withAlphaComponent(Glass.separatorAlpha).cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: 1).isActive = true
        view.heightAnchor.constraint(equalToConstant: 20).isActive = true
        return view
    }

    @objc private func editTapped() {
        DispatchQueue.main.async { [weak self] in self?.onEdit?() }
    }

    @objc private func closeTapped() {
        DispatchQueue.main.async { [weak self] in self?.onClose?() }
    }
}

private final class PinToolbarGripView: NSView {

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 22).isActive = true
        heightAnchor.constraint(equalToConstant: 28).isActive = true
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        context.saveGState()
        context.setLineCap(.round)
        context.setLineWidth(1.5)
        NSColor.white.withAlphaComponent(0.42).setStroke()

        let lineWidth: CGFloat = 11
        let centerX = bounds.midX
        for y in [bounds.midY - 4, bounds.midY, bounds.midY + 4] {
            context.move(to: CGPoint(x: centerX - lineWidth / 2, y: y))
            context.addLine(to: CGPoint(x: centerX + lineWidth / 2, y: y))
        }
        context.strokePath()
        context.restoreGState()
    }
}
