import AppKit

// MARK: - 矩形标注工具

/// 绘制矩形边框（不填充）
struct RectTool: AnnotationTool {
    let toolType: AnnotationToolType = .rectangle

    func draw(element: AnnotationElement, in context: CGContext) {
        let path = createPath(from: element.startPoint, to: element.endPoint)

        context.saveGState()

        // 设置描边颜色和线宽
        context.setStrokeColor(element.color.cgColor)
        context.setLineWidth(element.lineWidth)
        context.setLineCap(.square)
        context.setLineJoin(.miter)

        // 描边矩形
        context.addPath(path.toCGPath())
        context.strokePath()

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
