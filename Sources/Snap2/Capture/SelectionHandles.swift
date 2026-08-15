import AppKit

/// 选区把手共用逻辑：截图 / 录屏选区两套平行实现的收敛点。
/// 索引约定：0 TL / 1 TR / 2 BR / 3 BL（四角），4 T / 5 R / 6 B / 7 L（边中点）。
enum SelectionHandles {

    /// selecting 模式的标准把手尺寸（9pt）；标注模式用更小的 8pt，见调用方。
    static let size: CGFloat = 9
    /// 命中判定在手柄矩形基础上的外扩量。
    static let hitPad: CGFloat = 6

    static func rects(for selection: NSRect, handleSize: CGFloat = size) -> [NSRect] {
        guard selection.width > 0, selection.height > 0 else { return [] }
        let r = selection
        let s = handleSize
        let half = s / 2
        return [
            NSRect(x: r.minX - half, y: r.maxY - half, width: s, height: s), // 0 TL
            NSRect(x: r.maxX - half, y: r.maxY - half, width: s, height: s), // 1 TR
            NSRect(x: r.maxX - half, y: r.minY - half, width: s, height: s), // 2 BR
            NSRect(x: r.minX - half, y: r.minY - half, width: s, height: s), // 3 BL
            NSRect(x: r.midX - half, y: r.maxY - half, width: s, height: s), // 4 T
            NSRect(x: r.maxX - half, y: r.midY - half, width: s, height: s), // 5 R
            NSRect(x: r.midX - half, y: r.minY - half, width: s, height: s), // 6 B
            NSRect(x: r.minX - half, y: r.midY - half, width: s, height: s), // 7 L
        ]
    }

    /// 命中测试：返回命中的手柄索引（含 hitPad 外扩），未命中返回 nil。
    static func hitIndex(at p: NSPoint, in selection: NSRect, handleSize: CGFloat = size) -> Int? {
        for (i, h) in rects(for: selection, handleSize: handleSize).enumerated()
        where h.insetBy(dx: -hitPad, dy: -hitPad).contains(p) {
            return i
        }
        return nil
    }

    /// resize 时固定的对角锚点（角手柄用；边手柄锚点退化为 origin，由 resizedSelection 自行处理）。
    static func anchor(_ i: Int, of selection: NSRect) -> NSPoint {
        switch i {
        case 0: return NSPoint(x: selection.maxX, y: selection.minY)
        case 1: return NSPoint(x: selection.minX, y: selection.minY)
        case 2: return NSPoint(x: selection.minX, y: selection.maxY)
        case 3: return NSPoint(x: selection.maxX, y: selection.maxY)
        default: return selection.origin
        }
    }

    /// 把手柄 i 拖到点 p 后的新选区。anchor 为拖拽开始时的对角锚点。
    static func resizedSelection(handle i: Int, to p: NSPoint,
                                 from selection: NSRect, anchor: NSPoint) -> NSRect {
        switch i {
        case 0...3: // 角
            return NSRect(
                x: min(anchor.x, p.x), y: min(anchor.y, p.y),
                width: abs(p.x - anchor.x), height: abs(p.y - anchor.y)
            )
        case 4: // top
            let y = min(selection.minY, p.y)
            return NSRect(x: selection.minX, y: y, width: selection.width,
                          height: abs(p.y - selection.minY))
        case 5: // right
            let x = min(selection.minX, p.x)
            return NSRect(x: x, y: selection.minY, width: abs(p.x - selection.minX),
                          height: selection.height)
        case 6: // bottom
            let y = min(p.y, selection.maxY)
            return NSRect(x: selection.minX, y: y, width: selection.width,
                          height: abs(selection.maxY - p.y))
        case 7: // left
            let x = min(p.x, selection.maxX)
            return NSRect(x: x, y: selection.minY, width: abs(selection.maxX - p.x),
                          height: selection.height)
        default: return selection
        }
    }

    /// 手柄光标。四角统一用上下箭头——AppKit 没有公开的斜向 resize 光标。
    static func cursor(forHandle i: Int) -> NSCursor {
        let cursors: [NSCursor] = [
            .resizeUpDown, .resizeUpDown, .resizeUpDown, .resizeUpDown,   // 4 角
            .resizeUpDown, .resizeLeftRight, .resizeUpDown, .resizeLeftRight, // T R B L
        ]
        return cursors[i]
    }

    /// selecting 模式手柄绘制：白底圆点 + 暗色内描边 + 微阴影（任意背景可见）。
    static func drawSelecting(in context: CGContext, rects: [NSRect]) {
        context.saveGState()
        for rect in rects {
            let path = CGPath(ellipseIn: rect, transform: nil)
            context.setShadow(offset: CGSize(width: 0, height: -1), blur: 2,
                              color: NSColor.black.withAlphaComponent(0.4).cgColor)
            context.addPath(path)
            NSColor.white.setFill()
            context.fillPath()
            context.setShadow(offset: .zero, blur: 0, color: nil)

            context.addPath(path)
            NSColor(white: 0.0, alpha: 0.25).setStroke()
            context.setLineWidth(1.0)
            context.strokePath()
        }
        context.restoreGState()
    }
}
