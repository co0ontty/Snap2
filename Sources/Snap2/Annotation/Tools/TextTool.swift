import AppKit

// MARK: - 文字标注工具

/// 在指定位置绘制文字，带半透明背景
struct TextTool: AnnotationTool {
    let toolType: AnnotationToolType = .text

    /// 文字内边距
    private let textPadding: CGFloat = 6.0
    /// 背景圆角半径
    private let cornerRadius: CGFloat = 4.0
    /// 背景透明度
    private let backgroundAlpha: CGFloat = 0.2

    func draw(element: AnnotationElement, in context: CGContext) {
        guard let text = element.text, !text.isEmpty else { return }

        let font = element.font ?? NSFont.systemFont(ofSize: 16)
        let position = element.startPoint

        // 文字属性
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: element.color
        ]

        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedString.size()

        // 计算背景矩形（带内边距）
        let backgroundRect = NSRect(
            x: position.x - textPadding,
            y: position.y - textPadding,
            width: textSize.width + textPadding * 2,
            height: textSize.height + textPadding * 2
        )

        context.saveGState()

        // 绘制半透明背景
        let bgColor = NSColor.black.withAlphaComponent(backgroundAlpha)
        context.setFillColor(bgColor.cgColor)
        let bgPath = NSBezierPath(roundedRect: backgroundRect, xRadius: cornerRadius, yRadius: cornerRadius)
        context.addPath(bgPath.toCGPath())
        context.fillPath()

        context.restoreGState()

        // 绘制文字（使用 NSAttributedString 绘制）
        // 需要在 NSGraphicsContext 中绘制
        NSGraphicsContext.saveGraphicsState()
        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current = nsContext
        attributedString.draw(at: position)
        NSGraphicsContext.restoreGraphicsState()
    }

    func createPath(from startPoint: NSPoint, to endPoint: NSPoint) -> NSBezierPath {
        // 文字工具的路径是文字位置的一个标记点
        let path = NSBezierPath()
        let markerRect = NSRect(x: startPoint.x - 2, y: startPoint.y - 2, width: 4, height: 4)
        path.appendOval(in: markerRect)
        return path
    }
}
