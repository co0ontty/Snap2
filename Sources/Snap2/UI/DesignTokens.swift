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
    // 按下态：比 selected 稍亮即可，过亮会在按一下时显眼地"闪一下"
    static let pressedFill = NSColor.white.withAlphaComponent(0.30)

    // 间距
    static let toolbarPadX: CGFloat = 8
    static let toolbarPadY: CGFloat = 6
    static let buttonSize: CGFloat = 30
    static let groupSpacing: CGFloat = 6
    static let separatorAlpha: CGFloat = 0.28

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
        case .thin: return 5
        case .medium: return 9
        case .thick: return 13
        }
    }
}

// MARK: - Claude 暖橙 / 米白主题
//
// 设置窗口 + 欢迎窗口走 Claude 官网视觉：浅色下米白纸面 + 深棕字 + 橙强调；
// 深色下暖深棕底 + 米白字 + 提亮橙强调。所有 token 用 dynamicProvider 让 NSColor
// 自动跟随 effectiveAppearance；持久化到 CALayer 时记得在 viewDidChangeEffectiveAppearance
// 重新读取 .cgColor —— layer 持有的是 cgColor 快照，不会自己换色。
enum ClaudeTheme {
    private static func dyn(_ light: NSColor, _ dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            let mode = appearance.bestMatch(from: [.aqua, .darkAqua, .vibrantLight, .vibrantDark])
            let isDark = (mode == .darkAqua) || (mode == .vibrantDark)
            return isDark ? dark : light
        }
    }

    private static func srgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat(r) / 255.0,
                green: CGFloat(g) / 255.0,
                blue: CGFloat(b) / 255.0,
                alpha: a)
    }

    // —— 强调色 ——
    /// Claude Coral。按钮 / 选中态 / 描边主色。
    static let accent          = dyn(srgb(0xD9, 0x77, 0x57), srgb(0xE8, 0x89, 0x6C))
    /// 按下态 / hover 收紧时用的更深橙。
    static let accentPressed   = dyn(srgb(0xC4, 0x5F, 0x40), srgb(0xD9, 0x77, 0x57))

    // —— 底色与卡片 ——
    /// 窗体底色：浅色米白纸面 / 深色暖深棕。叠在 NSVisualEffectView 之上。
    static let cream           = dyn(srgb(0xF5, 0xF1, 0xE8), srgb(0x1F, 0x1B, 0x16))
    /// 卡片底色：比 cream 稍深一档。
    static let creamCard       = dyn(srgb(0xEE, 0xE8, 0xD6), srgb(0x2A, 0x24, 0x1D))
    /// 卡片 hover 时的更深一档。
    static let creamCardHover  = dyn(srgb(0xE6, 0xDD, 0xC4), srgb(0x33, 0x2C, 0x24))

    // —— 文字 ——
    /// 主文字色：浅色深棕 Bookish Brown / 深色米白。
    static let ink             = dyn(srgb(0x3D, 0x39, 0x29), srgb(0xF5, 0xF1, 0xE8))
    /// 次级文字。
    static let inkSecondary    = dyn(srgb(0x6B, 0x66, 0x57), srgb(0xC8, 0xC1, 0xAC))
    /// 三级 / placeholder。
    static let inkTertiary     = dyn(srgb(0x9A, 0x93, 0x7F), srgb(0x8F, 0x87, 0x75))

    // —— 描边 / 分隔 ——
    /// 玻璃细描边：浅色橙白边，深色暖白边。
    static let stroke          = dyn(srgb(0xD9, 0x77, 0x57).withAlphaComponent(0.22),
                                     srgb(0xF5, 0xF1, 0xE8).withAlphaComponent(0.18))
    /// 列表分隔线。
    static let hairline        = dyn(srgb(0x3D, 0x39, 0x29).withAlphaComponent(0.10),
                                     srgb(0xF5, 0xF1, 0xE8).withAlphaComponent(0.10))

    // —— 玻璃顶光 / 底光 ——
    /// 玻璃顶部白色高光（渐变起点）。
    static let topHighlight    = dyn(NSColor.white.withAlphaComponent(0.55),
                                     NSColor.white.withAlphaComponent(0.30))
    /// 玻璃底部暖光（渐变起点，从底部向上 8% 高度内可见）。
    static let bottomGlow      = dyn(srgb(0xD9, 0x77, 0x57).withAlphaComponent(0.10),
                                     srgb(0xD9, 0x77, 0x57).withAlphaComponent(0.06))
}

enum AnnotationPalette {
    /// 调色板：黑色置首，覆盖浅色截图（白底文档/网页）的标注需求；
    /// 白色保留以适配深色截图。
    static let colors: [NSColor] = [
        NSColor.black,
        NSColor(srgbRed: 1.00, green: 0.27, blue: 0.27, alpha: 1.0), // 红
        NSColor(srgbRed: 1.00, green: 0.78, blue: 0.18, alpha: 1.0), // 黄
        NSColor(srgbRed: 0.31, green: 0.84, blue: 0.42, alpha: 1.0), // 绿
        NSColor(srgbRed: 0.30, green: 0.65, blue: 1.00, alpha: 1.0), // 蓝
        NSColor.white,
    ]
}
