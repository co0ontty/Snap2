import AppKit

/// 单个标注元素的数据载体
final class AnnotationElement {
    var toolType: AnnotationToolType
    var color: NSColor
    var lineWidth: CGFloat
    var startPoint: NSPoint = .zero
    var endPoint: NSPoint = .zero
    var points: [NSPoint] = []
    var text: String?
    var font: NSFont?

    /// 马赛克专用：整张选区背景的 pixelated 版本（CGImage 引用，按需共享）
    var mosaicSource: CGImage?
    /// mosaicSource 对应的逻辑（点）尺寸 = 选区点尺寸
    var mosaicSourceSize: NSSize = .zero

    init(toolType: AnnotationToolType, color: NSColor, lineWidth: CGFloat) {
        self.toolType = toolType
        self.color = color
        self.lineWidth = lineWidth
    }
}

enum AnnotationToolType: Int, CaseIterable {
    case arrow = 0
    case rectangle
    case ellipse
    case freedraw
    case text
    case highlight
    case mosaic

    var displayName: String {
        switch self {
        case .arrow: return "箭头"
        case .rectangle: return "矩形"
        case .ellipse: return "椭圆"
        case .freedraw: return "画笔"
        case .text: return "文字"
        case .highlight: return "高亮"
        case .mosaic: return "马赛克"
        }
    }

    var symbolName: String {
        switch self {
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .freedraw: return "pencil.tip"
        case .text: return "textformat"
        case .highlight: return "highlighter"
        case .mosaic: return "square.grid.3x3.fill"
        }
    }

    /// 数字键快捷键（1–7）
    var shortcutDigit: Int { rawValue + 1 }
}
