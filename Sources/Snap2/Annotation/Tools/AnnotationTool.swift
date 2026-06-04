import AppKit

protocol AnnotationTool {
    var toolType: AnnotationToolType { get }
    func draw(element: AnnotationElement, in context: CGContext)
}

enum AnnotationDrawing {
    static func boundingRect(from startPoint: NSPoint, to endPoint: NSPoint) -> NSRect {
        NSRect(
            x: min(startPoint.x, endPoint.x),
            y: min(startPoint.y, endPoint.y),
            width: abs(endPoint.x - startPoint.x),
            height: abs(endPoint.y - startPoint.y)
        )
    }

    static func stroke(_ path: NSBezierPath,
                       element: AnnotationElement,
                       in context: CGContext,
                       lineCap: CGLineCap = .round,
                       lineJoin: CGLineJoin = .round) {
        context.saveGState()
        context.setStrokeColor(element.color.cgColor)
        context.setLineWidth(element.lineWidth)
        context.setLineCap(lineCap)
        context.setLineJoin(lineJoin)
        context.addPath(path.toCGPath())
        context.strokePath()
        context.restoreGState()
    }

    static func fill(_ path: NSBezierPath, color: NSColor, in context: CGContext) {
        context.saveGState()
        context.setFillColor(color.cgColor)
        context.addPath(path.toCGPath())
        context.fillPath()
        context.restoreGState()
    }
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
        register(MosaicTool())
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
