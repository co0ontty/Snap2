import AppKit

/// 选区尺寸徽章：截图 / 录屏选区共用。
/// 负责 GlassPanel 徽章的创建、文案更新与「选区上方优先、放不下翻下、钳制屏幕内」定位。
final class SizeBadge {

    private static let height: CGFloat = 28
    private static let minPanelWidth: CGFloat = 110

    private var panel: GlassPanel?
    private var label: NSTextField?

    /// 在父窗口上显示徽章（已显示时幂等）。
    func show(attachedTo parent: NSWindow?) {
        guard panel == nil else { return }
        let p = GlassPanel(size: NSSize(width: Self.minPanelWidth, height: Self.height),
                           cornerRadius: Glass.radiusBadge)
        let l = NSTextField(labelWithString: "")
        l.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        l.textColor = .white
        l.backgroundColor = .clear
        l.isBezeled = false
        l.isEditable = false
        l.alignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        p.contentBox.addSubview(l)
        NSLayoutConstraint.activate([
            l.centerXAnchor.constraint(equalTo: p.contentBox.centerXAnchor),
            l.centerYAnchor.constraint(equalTo: p.contentBox.centerYAnchor),
        ])
        if let parent = parent {
            parent.addChildWindow(p, ordered: .above)
        }
        p.orderFront(nil)
        panel = p
        label = l
    }

    /// 更新文案与位置。text 为已含前后空格的展示串（px 后缀有无由调用方决定）。
    func update(text: String, relativeTo selection: NSRect, in parentWindow: NSWindow) {
        guard let panel = panel, let label = label,
              selection.width > 0, selection.height > 0 else { return }

        label.stringValue = text
        label.sizeToFit()

        let w = max(Self.minPanelWidth, ceil(label.frame.width) + 24)
        panel.resize(to: NSSize(width: w, height: Self.height))

        // 位置：选区上方居中；放不下放下面；最后再钳制到屏幕可视区
        let so = parentWindow.frame.origin
        var x = so.x + selection.midX - w / 2
        var y = so.y + selection.maxY + 8
        let screenFrame = parentWindow.screen?.frame ?? parentWindow.frame
        if y + Self.height > so.y + screenFrame.height - 8 {
            y = so.y + selection.minY - Self.height - 8
        }
        x = max(so.x + 8, min(x, so.x + screenFrame.width - w - 8))
        y = max(so.y + 8, min(y, so.y + screenFrame.height - Self.height - 8))
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func hide() {
        if let p = panel {
            p.parent?.removeChildWindow(p)
            p.orderOut(nil)
        }
        panel = nil
        label = nil
    }
}
