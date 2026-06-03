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

        // 强制 P3 色彩空间：CopyToast 会在面板里展示截图缩略图（NSImage 自带 P3 ICC），
        // 若 window.colorSpace 留空，AppKit 在窗口创建时挑的 backing colorspace 是
        // 非确定性的，部分时刻会落到 sRGB——P3 像素被 gamut-clip 到 sRGB 再回到 P3
        // 显示器时，饱和色明显发暗发灰。锁死 displayP3 让 toast 与原始截图色一致；
        // 即便后续用于其它非缩略图场景（工具栏 / 尺寸徽章），P3 也对纯色 UI 无害。
        colorSpace = NSColorSpace.displayP3

        // 玻璃容器铺满
        let host = NSView(frame: NSRect(origin: .zero, size: size))
        host.wantsLayer = true
        host.layer?.masksToBounds = false
        host.layer?.shadowColor = Glass.shadowColor.cgColor
        host.layer?.shadowOpacity = 1
        host.layer?.shadowRadius = Glass.shadowRadius
        host.layer?.shadowOffset = Glass.shadowOffset
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
