import AppKit

// MARK: - 箭头标注工具

/// 绘制带箭头的线段
struct ArrowTool: AnnotationTool {
    let toolType: AnnotationToolType = .arrow

    /// 箭头长度系数（相对于线宽）
    private let arrowLengthFactor: CGFloat = 5.0
    /// 箭头角度（弧度）
    private let arrowAngle: CGFloat = .pi / 6.0  // 30度

    func draw(element: AnnotationElement, in context: CGContext) {
        context.saveGState()

        // 设置线条颜色和宽度
        context.setStrokeColor(element.color.cgColor)
        context.setFillColor(element.color.cgColor)
        context.setLineWidth(element.lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        // 绘制线段部分（描边）
        let linePath = NSBezierPath()
        linePath.move(to: element.startPoint)
        linePath.line(to: element.endPoint)
        linePath.lineWidth = element.lineWidth

        context.addPath(linePath.toCGPath())
        context.strokePath()

        // 绘制箭头部分（填充）
        let arrowPath = createArrowHead(
            from: element.startPoint,
            to: element.endPoint,
            lineWidth: element.lineWidth
        )
        context.addPath(arrowPath.toCGPath())
        context.fillPath()

        context.restoreGState()
    }

    func createPath(from startPoint: NSPoint, to endPoint: NSPoint) -> NSBezierPath {
        let path = NSBezierPath()

        // 线段部分
        path.move(to: startPoint)
        path.line(to: endPoint)

        // 箭头部分
        let arrowHead = createArrowHead(from: startPoint, to: endPoint, lineWidth: 2.0)
        path.append(arrowHead)

        return path
    }

    /// 创建箭头头部的三角形路径
    /// - Parameters:
    ///   - startPoint: 线段起始点
    ///   - endPoint: 线段结束点（箭头尖端）
    ///   - lineWidth: 线宽，用于缩放箭头大小
    /// - Returns: 箭头三角形的贝塞尔路径
    private func createArrowHead(from startPoint: NSPoint, to endPoint: NSPoint, lineWidth: CGFloat) -> NSBezierPath {
        let arrowLength = lineWidth * arrowLengthFactor
        let dx = endPoint.x - startPoint.x
        let dy = endPoint.y - startPoint.y
        let lineAngle = atan2(dy, dx)

        // 箭头两侧的点
        let arrowPoint1 = NSPoint(
            x: endPoint.x - arrowLength * cos(lineAngle - arrowAngle),
            y: endPoint.y - arrowLength * sin(lineAngle - arrowAngle)
        )
        let arrowPoint2 = NSPoint(
            x: endPoint.x - arrowLength * cos(lineAngle + arrowAngle),
            y: endPoint.y - arrowLength * sin(lineAngle + arrowAngle)
        )

        // 构建三角形
        let arrowPath = NSBezierPath()
        arrowPath.move(to: endPoint)
        arrowPath.line(to: arrowPoint1)
        arrowPath.line(to: arrowPoint2)
        arrowPath.close()

        return arrowPath
    }
}

