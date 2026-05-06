import AppKit

/// 钉在桌面上的浮动截图窗口。
/// - 始终置顶（.floating），可在所有 Space 显示
/// - 整个窗体可拖动，悬停显示关闭按钮
/// - 关闭后即从内存中释放，不进剪贴板、不写盘
final class PinnedImageWindow: NSPanel {

    /// 强引用所有打开的钉图，防止被释放
    private static var allPins: [PinnedImageWindow] = []

    private let imageView = DraggableImageView()
    private let closeButton = NSButton()
    private var trackingArea: NSTrackingArea?
    private var hoverToolbar: PinHoverToolbar?

    /// 当前钉图所显示的图片，给"重新标注"流程用
    var currentImage: NSImage { imageView.image ?? NSImage() }

    /// 在屏幕坐标 origin 处弹出钉图。
    @discardableResult
    static func show(image: NSImage, at screenOrigin: NSPoint) -> PinnedImageWindow {
        let pin = PinnedImageWindow(image: image, origin: screenOrigin)
        pin.alphaValue = 0
        pin.orderFront(nil)
        allPins.append(pin)

        // 入场：渐显 + 轻微下沉
        let target = NSPoint(x: screenOrigin.x, y: screenOrigin.y)
        pin.setFrameOrigin(NSPoint(x: target.x, y: target.y + 6))
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            pin.animator().alphaValue = 1.0
            pin.animator().setFrameOrigin(target)
        }
        return pin
    }

    private init(image: NSImage, origin: NSPoint) {
        let size = image.size
        super.init(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        ignoresMouseEvents = false

        // 圆角容器 + 极轻 1px 描边
        let host = NSView(frame: NSRect(origin: .zero, size: size))
        host.wantsLayer = true
        host.layer?.cornerRadius = 6
        host.layer?.cornerCurve = .continuous
        host.layer?.masksToBounds = true
        host.layer?.borderWidth = 1
        host.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        contentView = host

        // 图片
        imageView.frame = host.bounds
        imageView.autoresizingMask = [.width, .height]
        imageView.image = image
        imageView.imageScaling = .scaleAxesIndependently
        imageView.imageAlignment = .alignCenter
        imageView.pinWindow = self
        host.addSubview(imageView)

        // 关闭按钮（默认隐藏，悬停时淡入）
        let btnSize: CGFloat = 22
        let btnInset: CGFloat = 6
        closeButton.frame = NSRect(
            x: size.width - btnSize - btnInset,
            y: size.height - btnSize - btnInset,
            width: btnSize, height: btnSize
        )
        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.title = ""
        let xImg = NSImage(systemSymbolName: "xmark.circle.fill",
                           accessibilityDescription: "关闭")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 20, weight: .semibold))
        closeButton.image = xImg
        closeButton.contentTintColor = NSColor.white.withAlphaComponent(0.92)
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        closeButton.alphaValue = 0
        closeButton.toolTip = "关闭钉图"
        closeButton.autoresizingMask = [.minXMargin, .minYMargin]
        host.addSubview(closeButton)

        hoverToolbar = PinHoverToolbar(owner: self)

        installTrackingArea(on: host)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private func installTrackingArea(on view: NSView) {
        if let area = trackingArea { view.removeTrackingArea(area) }
        let area = NSTrackingArea(
            rect: view.bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        view.addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        hoverToolbar?.pinMouseEntered()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            closeButton.animator().alphaValue = 1.0
        }
    }

    override func mouseExited(with event: NSEvent) {
        hoverToolbar?.pinMouseExited()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.20
            closeButton.animator().alphaValue = 0.0
        }
    }

    @objc private func closeTapped() {
        // 异步派发：避免在 NSButton mouseDown tracking loop 内自释，
        // 与 GlassToolbar 的关闭键采用同样模式
        DispatchQueue.main.async { [weak self] in
            self?.dismissAnimated()
        }
    }

    func editFromHoverToolbar() {
        // 异步派发：CaptureManager 会 orderOut 自身，避免在 mouseDown loop 内拆窗
        hoverToolbar?.hideImmediately()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            CaptureManager.shared.editPin(self)
        }
    }

    func closeFromHoverToolbar() {
        closeTapped()
    }

    private func dismissAnimated() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0
            self.hoverToolbar?.hideImmediately()
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            self.hoverToolbar?.detach()
            self.orderOut(nil)
            PinnedImageWindow.allPins.removeAll { $0 === self }
        })
    }
}

/// NSImageView 默认会吃掉 mouseDown 阻断窗口拖动。
/// 这个子类把 mouseDown 转交给宿主窗口的 performDrag。
private final class DraggableImageView: NSImageView {
    weak var pinWindow: NSWindow?

    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        // 允许双击关闭：可选项，先不做
        pinWindow?.performDrag(with: event)
    }
}
