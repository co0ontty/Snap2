import AppKit

protocol AnnotationTool {
    var toolType: AnnotationToolType { get }
    func draw(element: AnnotationElement, in context: CGContext)
}

final class AnnotationToolRegistry {
    static let shared = AnnotationToolRegistry()

    private var tools: [AnnotationToolType: AnnotationTool] = [:]

    private init() {
        register(ArrowTool())
        register(RectTool())
        register(EllipseTool())
        register(FreedrawTool())
        register(TextTool())
        register(HighlightTool())
    }

    private func register(_ tool: AnnotationTool) {
        tools[tool.toolType] = tool
    }

    func tool(for type: AnnotationToolType) -> AnnotationTool? {
        tools[type]
    }
}

extension NSBezierPath {
    /// macOS 13 兼容：手动展开为 CGPath
    func toCGPath() -> CGPath {
        if #available(macOS 14.0, *) { return self.cgPath }
        let path = CGMutablePath()
        var points = [NSPoint](repeating: .zero, count: 3)
        for i in 0..<elementCount {
            switch element(at: i, associatedPoints: &points) {
            case .moveTo: path.move(to: points[0])
            case .lineTo: path.addLine(to: points[0])
            case .curveTo, .cubicCurveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .quadraticCurveTo:
                path.addQuadCurve(to: points[1], control: points[0])
            case .closePath: path.closeSubpath()
            @unknown default: break
            }
        }
        return path
    }
}
