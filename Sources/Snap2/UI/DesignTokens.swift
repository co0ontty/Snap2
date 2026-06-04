import AppKit

/// 全局视觉常量。改 token 等于改设计系统。
enum Glass {
    // 圆角
    static let radiusToolbar: CGFloat = 15
    static let radiusButton: CGFloat = 9
    static let radiusBadge: CGFloat = 9
    static let radiusCard: CGFloat = 16

    // 内描边
    static let strokeWidth: CGFloat = 1.0
    static let strokeColor = NSColor.white.withAlphaComponent(0.22)
    static let strokeColorStrong = NSColor.white.withAlphaComponent(0.36)

    // 顶部高光梯度
    static let topHighlight = NSColor.white.withAlphaComponent(0.34)
    static let topHighlightFade = NSColor.white.withAlphaComponent(0.0)

    // 阴影
    static let shadowColor = NSColor.black.withAlphaComponent(0.42)
    static let shadowRadius: CGFloat = 22
    static let shadowOffset = CGSize(width: 0, height: -3)

    // 按钮选中态
    static let selectedFill = NSColor.white.withAlphaComponent(0.18)
    static let hoverFill = NSColor.white.withAlphaComponent(0.11)
    // 按下态：比 selected 稍亮即可，过亮会在按一下时显眼地"闪一下"
    static let pressedFill = NSColor.white.withAlphaComponent(0.24)

    // 间距
    static let toolbarPadX: CGFloat = 8
    static let toolbarPadY: CGFloat = 6
    static let buttonSize: CGFloat = 30
    static let groupSpacing: CGFloat = 6
    static let separatorAlpha: CGFloat = 0.22

    // 动画
    static let animDuration: CFTimeInterval = 0.18

    static func separator(height: CGFloat) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.white.withAlphaComponent(separatorAlpha).cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: 1).isActive = true
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        return view
    }
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

// MARK: - Snap 暖纸 / 冷中性玻璃主题
//
// 设置窗口 + 欢迎窗口走暖纸面 + 冷中性玻璃：浅色下干净纸面 + 深墨字 + 珊瑚强调；
// 深色下炭黑微暖底 + 米白字 + 提亮珊瑚强调。所有 token 用 dynamicProvider 让 NSColor
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
    /// Snap Coral。按钮 / 选中态 / 描边主色。
    static let accent          = dyn(srgb(0xC9, 0x6D, 0x4B), srgb(0xF0, 0x88, 0x66))
    /// 按下态 / hover 收紧时用的更深珊瑚色。
    static let accentPressed   = dyn(srgb(0xA8, 0x56, 0x38), srgb(0xD9, 0x6F, 0x52))
    /// 低强度强调底色。
    static let accentSoft      = dyn(srgb(0xC9, 0x6D, 0x4B).withAlphaComponent(0.13),
                                     srgb(0xF0, 0x88, 0x66).withAlphaComponent(0.18))
    /// 选中 / 聚焦描边。
    static let focusRing       = dyn(srgb(0xC9, 0x6D, 0x4B).withAlphaComponent(0.50),
                                     srgb(0xF0, 0x88, 0x66).withAlphaComponent(0.62))
    /// 强调阴影。
    static let accentShadow    = dyn(srgb(0xC9, 0x6D, 0x4B).withAlphaComponent(0.18),
                                     srgb(0xF0, 0x88, 0x66).withAlphaComponent(0.22))
    /// 辅助冷色，只用于图标底、装饰光和少量状态，打破纯暖色单调。
    static let secondaryAccent = dyn(srgb(0x3F, 0x7E, 0x75), srgb(0x7F, 0xD8, 0xC7))
    static let secondarySoft   = dyn(srgb(0x3F, 0x7E, 0x75).withAlphaComponent(0.11),
                                     srgb(0x7F, 0xD8, 0xC7).withAlphaComponent(0.14))

    // —— 底色与卡片 ——
    /// 窗体底色：浅色暖纸面 / 深色冷中性炭黑。叠在 NSVisualEffectView 之上。
    static let cream           = dyn(srgb(0xF7, 0xF3, 0xEA), srgb(0x19, 0x1C, 0x1A))
    /// 侧边栏底色，略冷、略重，保证导航和内容区有清晰分区。
    static let sidebarTint     = dyn(srgb(0xEE, 0xE8, 0xDB), srgb(0x1F, 0x23, 0x20))
    /// 卡片底色：更接近白纸，减少大面积米黄色。
    static let creamCard       = dyn(srgb(0xFE, 0xFC, 0xF7), srgb(0x25, 0x27, 0x24))
    /// 卡片 hover 时的更深一档。
    static let creamCardHover  = dyn(srgb(0xF4, 0xEF, 0xE4), srgb(0x31, 0x33, 0x2F))
    /// 输入、录制框等轻量控制的底色。
    static let controlFill     = dyn(NSColor.white.withAlphaComponent(0.58),
                                     NSColor.white.withAlphaComponent(0.08))
    static let controlHover    = dyn(NSColor.white.withAlphaComponent(0.82),
                                     NSColor.white.withAlphaComponent(0.13))
    static let selectionFill   = dyn(srgb(0xC9, 0x6D, 0x4B).withAlphaComponent(0.15),
                                     srgb(0xF0, 0x88, 0x66).withAlphaComponent(0.18))

    // —— 文字 ——
    /// 主文字色：浅色墨棕 / 深色暖白。
    static let ink             = dyn(srgb(0x25, 0x25, 0x20), srgb(0xF8, 0xF2, 0xE8))
    /// 次级文字。
    static let inkSecondary    = dyn(srgb(0x67, 0x63, 0x59), srgb(0xC9, 0xC4, 0xB6))
    /// 三级 / placeholder。
    static let inkTertiary     = dyn(srgb(0x98, 0x92, 0x84), srgb(0x91, 0x8D, 0x80))

    // —— 描边 / 分隔 ——
    /// 玻璃细描边：浅色暖灰边，深色暖白边。
    static let stroke          = dyn(srgb(0x99, 0x80, 0x69).withAlphaComponent(0.24),
                                     srgb(0xF8, 0xF2, 0xE8).withAlphaComponent(0.16))
    /// 列表分隔线。
    static let hairline        = dyn(srgb(0x25, 0x25, 0x20).withAlphaComponent(0.09),
                                     srgb(0xF8, 0xF2, 0xE8).withAlphaComponent(0.10))

    // —— 玻璃顶光 / 底光 ——
    /// 玻璃顶部白色高光（渐变起点）。
    static let topHighlight    = dyn(NSColor.white.withAlphaComponent(0.62),
                                     NSColor.white.withAlphaComponent(0.28))
    /// 玻璃底部暖光（渐变起点，从底部向上 8% 高度内可见）。
    static let bottomGlow      = dyn(srgb(0xC9, 0x6D, 0x4B).withAlphaComponent(0.11),
                                     srgb(0xF0, 0x88, 0x66).withAlphaComponent(0.07))
    /// 右上角的冷色折光，轻微平衡暖色主题。
    static let sideGlow        = dyn(srgb(0x3F, 0x7E, 0x75).withAlphaComponent(0.07),
                                     srgb(0x7F, 0xD8, 0xC7).withAlphaComponent(0.05))
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
