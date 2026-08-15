import AppKit

/// 全局视觉常量。改 token 等于改设计系统。
///
/// 两套体系：
/// - `Glass`：截图 HUD（工具栏/徽章/Toast/录制面板）——深色毛玻璃 + 扁平填充，
///   悬浮在任意屏幕内容之上，只保留保证可读性的最少层次。
/// - `Layout`：设置窗 / 欢迎窗的间距与字号体系。
/// 界面颜色一律用系统动态色（controlAccentColor / labelColor / separatorColor…），
/// 自动跟随明暗与用户强调色偏好。
enum Glass {
    // 圆角
    static let radiusToolbar: CGFloat = 10
    static let radiusButton: CGFloat = 6
    static let radiusBadge: CGFloat = 6
    static let radiusCard: CGFloat = 10

    // 内描边
    static let strokeWidth: CGFloat = 1.0
    static let strokeColor = NSColor.white.withAlphaComponent(0.16)

    // 阴影
    static let shadowColor = NSColor.black.withAlphaComponent(0.35)
    static let shadowRadius: CGFloat = 12
    static let shadowOffset = CGSize(width: 0, height: -2)

    // 按钮态：无描边、纯填充
    static let hoverFill = NSColor.white.withAlphaComponent(0.12)
    // 按下态：比选中稍亮即可，过亮会在按一下时显眼地"闪一下"
    static let pressedFill = NSColor.white.withAlphaComponent(0.20)

    // 间距
    static let buttonSize: CGFloat = 28
    static let groupSpacing: CGFloat = 6
    static let separatorAlpha: CGFloat = 0.16

    // 动画
    static let animDuration: CFTimeInterval = 0.15

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

/// 设置窗 / 欢迎窗共用的布局体系：统一边距、行高与字号。
enum Layout {
    /// 内容区左右/顶部边距。
    static let contentInset: CGFloat = 24
    /// 设置行高。
    static let rowHeight: CGFloat = 44
    /// 分区之间的垂直间距。
    static let sectionGap: CGFloat = 28

    /// 页面大标题。
    static let titleFont = NSFont.systemFont(ofSize: 20, weight: .semibold)
    /// 页面副标题 / 说明文字。
    static let subtitleFont = NSFont.systemFont(ofSize: 12)
    /// 分区标题。
    static let sectionFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
    /// 行主标签。
    static let rowFont = NSFont.systemFont(ofSize: 13)
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
