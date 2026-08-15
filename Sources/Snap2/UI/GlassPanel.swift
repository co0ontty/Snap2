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
        // backing colorspace 若落到 sRGB，饱和色会 gamut-clip 变暗发灰。
        // 详细背景见 PanelFX.adoptDisplayP3。
        PanelFX.adoptDisplayP3(self)

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
