import AppKit

// MARK: - 椭圆标注工具

/// 绘制椭圆边框（不填充），用矩形包围盒定义椭圆
struct EllipseTool: AnnotationTool {
    let toolType: AnnotationToolType = .ellipse

    func draw(element: AnnotationElement, in context: CGContext) {
        let path = createPath(from: element.startPoint, to: element.endPoint)
        AnnotationDrawing.stroke(path, element: element, in: context)
    }

    func createPath(from startPoint: NSPoint, to endPoint: NSPoint) -> NSBezierPath {
        NSBezierPath(ovalIn: AnnotationDrawing.boundingRect(from: startPoint, to: endPoint))
    }
}
