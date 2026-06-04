import AppKit

// MARK: - 矩形标注工具

/// 绘制矩形边框（不填充）
struct RectTool: AnnotationTool {
    let toolType: AnnotationToolType = .rectangle

    func draw(element: AnnotationElement, in context: CGContext) {
        let path = createPath(from: element.startPoint, to: element.endPoint)
        AnnotationDrawing.stroke(path, element: element, in: context, lineCap: .square, lineJoin: .miter)
    }

    func createPath(from startPoint: NSPoint, to endPoint: NSPoint) -> NSBezierPath {
        NSBezierPath(rect: AnnotationDrawing.boundingRect(from: startPoint, to: endPoint))
    }
}
