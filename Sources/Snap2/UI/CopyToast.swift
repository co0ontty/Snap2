import AppKit

/// 复制 / 保存成功后的玻璃 toast。屏幕右上角弹出，含缩略图，1.4s 后自动消失。
/// 之所以挪到右上：右下角与系统 Dock / 常驻浮窗位置冲突，且通知向下滑出和
/// macOS 原生通知中心方向相反，反而显眼；改到右上后与系统通知一致。
final class CopyToast {

    private static var current: GlassPanel?

    static func show(image: NSImage,
                     message: String = "已复制到剪贴板",
                     subtitle: String = "⌘V 粘贴")
    {
        // 立刻做一份小缩略图，避免 toast 在屏上 1.4s 期间一直持有整张 4K/5K 原图。
        let thumbnail = makeThumbnail(of: image, maxDimension: 128)
        DispatchQueue.main.async {
            current?.orderOut(nil)
            current = nil
            present(image: thumbnail, message: message, subtitle: subtitle)
        }
    }

    /// 按原图比例缩到 maxDimension 内，返回新 NSImage。原图不再被 toast retain。
    private static func makeThumbnail(of image: NSImage, maxDimension: CGFloat) -> NSImage {
        let s = image.size
        guard s.width > 0, s.height > 0 else { return image }
        let scale = min(1.0, maxDimension / max(s.width, s.height))
        let target = NSSize(width: max(1, round(s.width * scale)),
                            height: max(1, round(s.height * scale)))
        let thumb = NSImage(size: target)
        thumb.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: target),
                   from: .zero,
                   operation: .copy,
                   fraction: 1.0)
        thumb.unlockFocus()
        return thumb
    }

    private static func present(image: NSImage, message: String, subtitle: String) {
        guard let screen = NSScreen.main else { return }

        // 缩略图容器 56×40 长方形，按原图比例 .scaleProportionallyDown 保留宽高比，
        // 避免长截图/超宽截图被压成方块看不清。
        let thumbBoxW: CGFloat = 56
        let thumbBoxH: CGFloat = 40
        let size = NSSize(width: 280, height: 68)
        let panel = GlassPanel(size: size, cornerRadius: 18, level: .floating)

        let host = panel.contentBox

        let thumbY = (size.height - thumbBoxH) / 2
        let thumb = NSImageView(frame: NSRect(x: 14, y: thumbY,
                                              width: thumbBoxW, height: thumbBoxH))
        thumb.imageScaling = .scaleProportionallyDown
        thumb.imageAlignment = .alignCenter
        thumb.image = image
        thumb.wantsLayer = true
        thumb.layer?.cornerRadius = 6
        thumb.layer?.masksToBounds = true
        thumb.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        thumb.layer?.borderWidth = 1
        host.addSubview(thumb)

        let textLeft: CGFloat = 14 + thumbBoxW + 12
        let textWidth = size.width - textLeft - 14

        // 主标签
        let title = NSTextField(labelWithString: message)
        title.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .white
        title.backgroundColor = .clear
        title.isBezeled = false
        title.isEditable = false
        title.frame = NSRect(x: textLeft, y: 34, width: textWidth, height: 18)
        host.addSubview(title)

        // 副标签
        let sub = NSTextField(labelWithString: subtitle)
        sub.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        sub.textColor = NSColor.white.withAlphaComponent(0.65)
        sub.backgroundColor = .clear
        sub.isBezeled = false
        sub.isEditable = false
        sub.lineBreakMode = .byTruncatingMiddle
        sub.frame = NSRect(x: textLeft, y: 14, width: textWidth, height: 16)
        host.addSubview(sub)

        // 屏幕右上角（与 macOS 系统通知方向一致）
        let visibleFrame = screen.visibleFrame
        let margin: CGFloat = 24
        let origin = NSPoint(
            x: visibleFrame.maxX - size.width - margin,
            y: visibleFrame.maxY - size.height - margin
        )
        panel.setFrameOrigin(origin)
        panel.alphaValue = 0
        panel.orderFront(nil)
        current = panel

        // 入场：从上方滑入 + 渐显
        let from = NSPoint(x: origin.x, y: origin.y + 24)
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
