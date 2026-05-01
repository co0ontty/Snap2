import AppKit

/// 复制成功后的玻璃 toast。屏幕右下角弹出，含缩略图，1.4s 后自动消失。
final class CopyToast {

    private static var current: GlassPanel?

    static func show(image: NSImage,
                     message: String = "已复制到剪贴板",
                     subtitle: String = "Enter 截图 / ⌘V 粘贴")
    {
        DispatchQueue.main.async {
            current?.orderOut(nil)
            current = nil
            present(image: image, message: message, subtitle: subtitle)
        }
    }

    private static func present(image: NSImage, message: String, subtitle: String) {
        guard let screen = NSScreen.main else { return }

        let size = NSSize(width: 280, height: 76)
        let panel = GlassPanel(size: size, cornerRadius: 18, level: .floating)

        let host = panel.contentBox

        // 缩略图
        let thumb = NSImageView(frame: NSRect(x: 14, y: 14, width: 48, height: 48))
        thumb.imageScaling = .scaleProportionallyUpOrDown
        thumb.image = image
        thumb.wantsLayer = true
        thumb.layer?.cornerRadius = 8
        thumb.layer?.masksToBounds = true
        thumb.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        thumb.layer?.borderWidth = 1
        host.addSubview(thumb)

        // 主标签
        let title = NSTextField(labelWithString: message)
        title.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .white
        title.backgroundColor = .clear
        title.isBezeled = false
        title.isEditable = false
        title.frame = NSRect(x: 76, y: 38, width: size.width - 90, height: 18)
        host.addSubview(title)

        // 副标签
        let sub = NSTextField(labelWithString: subtitle)
        sub.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        sub.textColor = NSColor.white.withAlphaComponent(0.65)
        sub.backgroundColor = .clear
        sub.isBezeled = false
        sub.isEditable = false
        sub.lineBreakMode = .byTruncatingMiddle
        sub.frame = NSRect(x: 76, y: 18, width: size.width - 90, height: 16)
        host.addSubview(sub)

        // 屏幕右下角
        let visibleFrame = screen.visibleFrame
        let margin: CGFloat = 24
        let origin = NSPoint(
            x: visibleFrame.maxX - size.width - margin,
            y: visibleFrame.minY + margin
        )
        panel.setFrameOrigin(origin)
        panel.alphaValue = 0
        panel.orderFront(nil)
        current = panel

        // 入场：从下方滑入 + 渐显
        let from = NSPoint(x: origin.x, y: origin.y - 24)
        panel.setFrameOrigin(from)

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1.0
            panel.animator().setFrameOrigin(origin)
        }, completionHandler: nil)

        // 1.4s 后自动消失
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            guard current === panel else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0.0
            }, completionHandler: {
                panel.orderOut(nil)
                if current === panel { current = nil }
            })
        }
    }
}
