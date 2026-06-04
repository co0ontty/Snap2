import AppKit

// MARK: - 高亮标注工具

/// 半透明矩形高亮标记
struct HighlightTool: AnnotationTool {
    let toolType: AnnotationToolType = .highlight

    /// 高亮透明度
    private let highlightAlpha: CGFloat = 0.3

    func draw(element: AnnotationElement, in context: CGContext) {
        let path = createPath(from: element.startPoint, to: element.endPoint)
        let highlightColor = element.color.withAlphaComponent(highlightAlpha)
        AnnotationDrawing.fill(path, color: highlightColor, in: context)
    }

    func createPath(from startPoint: NSPoint, to endPoint: NSPoint) -> NSBezierPath {
        NSBezierPath(rect: AnnotationDrawing.boundingRect(from: startPoint, to: endPoint))
    }
}
