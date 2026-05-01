import AppKit

// MARK: - 椭圆标注工具

/// 绘制椭圆边框（不填充），用矩形包围盒定义椭圆
struct EllipseTool: AnnotationTool {
    let toolType: AnnotationToolType = .ellipse

    func draw(element: AnnotationElement, in context: CGContext) {
        let path = createPath(from: element.startPoint, to: element.endPoint)

        context.saveGState()

        // 设置描边颜色和线宽
        context.setStrokeColor(element.color.cgColor)
        context.setLineWidth(element.lineWidth)
        context.setLineCap(.round)

        // 描边椭圆
        context.addPath(path.toCGPath())
        context.strokePath()

        context.restoreGState()
    }

    func createPath(from startPoint: NSPoint, to endPoint: NSPoint) -> NSBezierPath {
        // 根据起始点和结束点计算包围矩形
        let rect = NSRect(
            x: min(startPoint.x, endPoint.x),
            y: min(startPoint.y, endPoint.y),
            width: abs(endPoint.x - startPoint.x),
            height: abs(endPoint.y - startPoint.y)
        )
        return NSBezierPath(ovalIn: rect)
    }
}
