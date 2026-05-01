import AppKit

// MARK: - 高亮标注工具

/// 半透明矩形高亮标记
struct HighlightTool: AnnotationTool {
    let toolType: AnnotationToolType = .highlight

    /// 高亮透明度
    private let highlightAlpha: CGFloat = 0.3

    func draw(element: AnnotationElement, in context: CGContext) {
        let path = createPath(from: element.startPoint, to: element.endPoint)

        context.saveGState()

        // 使用半透明颜色填充矩形
        let highlightColor = element.color.withAlphaComponent(highlightAlpha)
        context.setFillColor(highlightColor.cgColor)

        context.addPath(path.toCGPath())
        context.fillPath()

        context.restoreGState()
    }

    func createPath(from startPoint: NSPoint, to endPoint: NSPoint) -> NSBezierPath {
        // 根据起始点和结束点计算矩形区域
        let rect = NSRect(
            x: min(startPoint.x, endPoint.x),
            y: min(startPoint.y, endPoint.y),
            width: abs(endPoint.x - startPoint.x),
            height: abs(endPoint.y - startPoint.y)
        )
        return NSBezierPath(rect: rect)
    }
}
