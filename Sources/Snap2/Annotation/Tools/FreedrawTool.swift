import AppKit

// MARK: - 自由画笔标注工具

/// 自由画笔工具，使用贝塞尔曲线平滑连接各点
struct FreedrawTool: AnnotationTool {
    let toolType: AnnotationToolType = .freedraw

    func draw(element: AnnotationElement, in context: CGContext) {
        guard element.points.count >= 2 else { return }

        let path = createSmoothPath(from: element.points)

        context.saveGState()

        // 设置描边颜色和线宽
        context.setStrokeColor(element.color.cgColor)
        context.setLineWidth(element.lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        // 描边路径
        context.addPath(path.toCGPath())
        context.strokePath()

        context.restoreGState()
    }

    func createPath(from startPoint: NSPoint, to endPoint: NSPoint) -> NSBezierPath {
        // 对于自由画笔，简单的两点直线
        let path = NSBezierPath()
        path.move(to: startPoint)
        path.line(to: endPoint)
        return path
    }

    /// 使用贝塞尔曲线平滑连接多个点
    /// - Parameter points: 点的数组
    /// - Returns: 平滑的贝塞尔路径
    private func createSmoothPath(from points: [NSPoint]) -> NSBezierPath {
        let path = NSBezierPath()

        guard let firstPoint = points.first else { return path }
        path.move(to: firstPoint)

        if points.count == 2 {
            // 只有两个点，画直线
            path.line(to: points[1])
            return path
        }

        // 使用 Catmull-Rom 样条算法平滑曲线
        for i in 1..<points.count {
            let currentPoint = points[i]
            let previousPoint = points[i - 1]

            // 计算中间控制点
            let midPoint = NSPoint(
                x: (previousPoint.x + currentPoint.x) / 2.0,
                y: (previousPoint.y + currentPoint.y) / 2.0
            )

            if i == 1 {
                // 第一段用二次曲线
                path.addQuadCurve(to: midPoint, controlPoint: previousPoint)
            } else {
                // 后续段用二次曲线，控制点是前一个点
                let prevMidPoint = NSPoint(
                    x: (points[i - 2].x + previousPoint.x) / 2.0,
                    y: (points[i - 2].y + previousPoint.y) / 2.0
                )
                path.addCurve(to: midPoint, controlPoint1: prevMidPoint, controlPoint2: previousPoint)
            }
        }

        // 连接到最后一个点
        if let lastPoint = points.last {
            path.line(to: lastPoint)
        }

        return path
    }
}

// MARK: - NSBezierPath 二次贝塞尔曲线扩展

extension NSBezierPath {
    /// 添加二次贝塞尔曲线（NSBezierPath 原生不支持，需手动转换为三次曲线）
    func addQuadCurve(to endPoint: NSPoint, controlPoint: NSPoint) {
        let startPoint = currentPoint

        // 将二次曲线转换为三次曲线
        let cp1 = NSPoint(
            x: startPoint.x + 2.0 / 3.0 * (controlPoint.x - startPoint.x),
            y: startPoint.y + 2.0 / 3.0 * (controlPoint.y - startPoint.y)
        )
        let cp2 = NSPoint(
            x: endPoint.x + 2.0 / 3.0 * (controlPoint.x - endPoint.x),
            y: endPoint.y + 2.0 / 3.0 * (controlPoint.y - endPoint.y)
        )

        curve(to: endPoint, controlPoint1: cp1, controlPoint2: cp2)
    }

    /// 添加三次贝塞尔曲线（别名，使接口更清晰）
    func addCurve(to endPoint: NSPoint, controlPoint1: NSPoint, controlPoint2: NSPoint) {
        curve(to: endPoint, controlPoint1: controlPoint1, controlPoint2: controlPoint2)
    }
}
