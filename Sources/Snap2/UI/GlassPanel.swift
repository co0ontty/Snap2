import AppKit

/// 玻璃浮动面板。borderless + nonactivating，承载工具栏、Toast、徽章。
final class GlassPanel: NSPanel {

    let glass = GlassEffectView()

    init(size: NSSize, cornerRadius: CGFloat = Glass.radiusToolbar, level: NSWindow.Level = .screenSaver + 1) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = level
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        ignoresMouseEvents = false

        // 玻璃容器铺满
        let host = NSView(frame: NSRect(origin: .zero, size: size))
        host.wantsLayer = true
        host.layer?.masksToBounds = false
        contentView = host

        glass.cornerRadius = cornerRadius
        glass.frame = host.bounds
        glass.autoresizingMask = [.width, .height]
        host.addSubview(glass)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// 子视图直接加到这里
    var contentBox: NSView { glass.contentView }

    /// 设置面板尺寸（保留位置）
    func resize(to size: NSSize) {
        var f = frame
        f.size = size
        setFrame(f, display: false, animate: false)
    }
}
