import AppKit

/// 悬浮面板（GlassPanel 等 borderless 窗口）的通用动效 / 定位 / 色彩空间工具。
/// 收敛此前散落在 SelectionView、RecordingSelectionView、RecordingControlPanel、
/// CopyToast 里的四份平行实现。
enum PanelFX {

    enum SlideDirection {
        /// 从目标位下方升起（选区下方的工具栏/确认条）。
        case up
        /// 从目标位上方落下（屏幕右上角的面板）。
        case down
    }

    /// HUD 面板标准入场：淡入并沿 slide 方向滑升/落下到位。
    static func animateIn(panel: NSWindow, to target: NSPoint,
                          rise: CGFloat = 12, duration: TimeInterval = 0.2,
                          slide: SlideDirection = .up,
                          completion: (() -> Void)? = nil) {
        let from = NSPoint(x: target.x, y: slide == .up ? target.y - rise : target.y + rise)
        panel.alphaValue = 0
        panel.setFrameOrigin(from)
        panel.orderFront(nil)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1.0
            panel.animator().setFrameOrigin(target)
        }, completionHandler: completion)
    }

    /// 屏幕可视区右上角原点（与系统通知一致的角落）。
    static func topRightOrigin(panelSize: NSSize, in screen: NSScreen?,
                               margin: CGFloat = 16) -> NSPoint {
        let visible = (screen ?? NSScreen.main)?.visibleFrame ?? .zero
        return NSPoint(x: visible.maxX - panelSize.width - margin,
                       y: visible.maxY - panelSize.height - margin)
    }

    /// 截图 / 钉图窗口使用 displayP3 色彩空间：捕获内容本来就是 P3，
    /// 交给默认 sRGB 窗口会 gamut-clip（饱和色变暗），这里保持全链路 P3。
    static func adoptDisplayP3(_ window: NSWindow) {
        window.colorSpace = .displayP3
    }
}

extension NSView {
    /// 重建覆盖整个 bounds 的 hover 追踪区（收敛各类自定义控件里重复的样板）。
    /// owner 默认 self；需要 cursorUpdate 等额外行为时传 options。
    func rebuildHoverTrackingArea(existing: inout NSTrackingArea?,
                                  options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]) {
        if let a = existing { removeTrackingArea(a) }
        let a = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(a)
        existing = a
    }
}
