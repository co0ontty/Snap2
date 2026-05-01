import AppKit

/// 全局视觉常量。改 token 等于改设计系统。
enum Glass {
    // 圆角
    static let radiusToolbar: CGFloat = 16
    static let radiusButton: CGFloat = 10
    static let radiusBadge: CGFloat = 10
    static let radiusCard: CGFloat = 18

    // 内描边
    static let strokeWidth: CGFloat = 1.0
    static let strokeColor = NSColor.white.withAlphaComponent(0.18)
    static let strokeColorStrong = NSColor.white.withAlphaComponent(0.28)

    // 顶部高光梯度
    static let topHighlight = NSColor.white.withAlphaComponent(0.30)
    static let topHighlightFade = NSColor.white.withAlphaComponent(0.0)

    // 阴影
    static let shadowColor = NSColor.black.withAlphaComponent(0.50)
    static let shadowRadius: CGFloat = 24
    static let shadowOffset = CGSize(width: 0, height: -4)

    // 按钮选中态
    static let selectedFill = NSColor.white.withAlphaComponent(0.22)
    static let hoverFill = NSColor.white.withAlphaComponent(0.10)
    static let pressedFill = NSColor.white.withAlphaComponent(0.30)

    // 间距
    static let toolbarPadX: CGFloat = 8
    static let toolbarPadY: CGFloat = 6
    static let buttonSize: CGFloat = 30
    static let groupSpacing: CGFloat = 6
    static let separatorAlpha: CGFloat = 0.18

    // 动画
    static let animDuration: CFTimeInterval = 0.18
}

enum LineWidthLevel: CGFloat, CaseIterable {
    case thin = 1.5
    case medium = 3.0
    case thick = 5.5

    var label: String {
        switch self {
        case .thin: return "细"
        case .medium: return "中"
        case .thick: return "粗"
        }
    }

    var dotSize: CGFloat {
        switch self {
        case .thin: return 4
        case .medium: return 7
        case .thick: return 10
        }
    }
}

enum AnnotationPalette {
    static let colors: [NSColor] = [
        NSColor(srgbRed: 1.00, green: 0.27, blue: 0.27, alpha: 1.0), // 红
        NSColor(srgbRed: 1.00, green: 0.78, blue: 0.18, alpha: 1.0), // 黄
        NSColor(srgbRed: 0.31, green: 0.84, blue: 0.42, alpha: 1.0), // 绿
        NSColor(srgbRed: 0.30, green: 0.65, blue: 1.00, alpha: 1.0), // 蓝
        NSColor.white,
    ]
}
