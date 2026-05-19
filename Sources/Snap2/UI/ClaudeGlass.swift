import AppKit
import QuartzCore

/// Claude 风格液态玻璃栈。设置窗 / 欢迎窗复用。
///
/// 渲染层栈（从下到上）：
/// 1. NSVisualEffectView (`.windowBackground` + `.behindWindow`) —— 模糊壁纸
/// 2. cream tint layer —— 米白/暖棕染色（让玻璃成纸质感）
/// 3. top highlight gradient —— 顶部白色高光
/// 4. bottom glow gradient —— 底部 Claude 橙暖光
///
/// 用法：`ClaudeGlass.install(into: contentView)` —— 自动把 4 层铺到 host 全尺寸，
/// 后续把 UI 直接 add 到 contentView 即可。
///
/// 注意：CALayer 持有的 cgColor 是快照，不会随系统明暗切换刷新。本工具内部用
/// `ClaudeGlassHostView` 监听 `viewDidChangeEffectiveAppearance`，自己把
/// tint/top/bottom 三层 cgColor 重读一遍。
enum ClaudeGlass {

    /// 安装到 host 全尺寸。host 必须有非零 frame 或 autoresizing 约束。
    /// 返回安装好的 host view 句柄；调用方一般不需要它，但保留给后续动态变更入口。
    @discardableResult
    static func install(into host: NSView) -> ClaudeGlassHostView {
        // 复用：如果已安装过则不重复挂层
        if let existing = host.subviews.compactMap({ $0 as? ClaudeGlassHostView }).first {
            return existing
        }
        let view = ClaudeGlassHostView(frame: host.bounds)
        view.autoresizingMask = [.width, .height]
        host.addSubview(view, positioned: .below, relativeTo: nil)
        return view
    }
}

/// 承载 4 层玻璃的 NSView。监听 effectiveAppearance 切换。
final class ClaudeGlassHostView: NSView {

    private let blur = NSVisualEffectView()
    private let tintLayer = CALayer()
    private let topHighlight = CAGradientLayer()
    private let bottomGlow = CAGradientLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        // 1) 模糊层
        blur.material = .windowBackground   // 浅色透出米白、深色透出暗灰；上面再叠 cream tint 补暖
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.autoresizingMask = [.width, .height]
        blur.frame = bounds
        addSubview(blur)

        // 2) cream tint
        tintLayer.frame = bounds
        layer?.addSublayer(tintLayer)

        // 3) 顶部高光
        topHighlight.frame = bounds
        topHighlight.startPoint = CGPoint(x: 0.5, y: 1.0)
        topHighlight.endPoint = CGPoint(x: 0.5, y: 0.45)
        topHighlight.locations = [0.0, 1.0]
        layer?.addSublayer(topHighlight)

        // 4) 底部暖光
        bottomGlow.frame = bounds
        bottomGlow.startPoint = CGPoint(x: 0.5, y: 0.0)
        bottomGlow.endPoint = CGPoint(x: 0.5, y: 0.08)
        bottomGlow.locations = [0.0, 1.0]
        layer?.addSublayer(bottomGlow)

        refreshColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        tintLayer.frame = bounds
        topHighlight.frame = bounds
        bottomGlow.frame = bounds
        CATransaction.commit()
    }

    /// 玻璃只负责绘制，不该吃任何鼠标事件——让 isMovableByWindowBackground 继续生效。
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }

    private func refreshColors() {
        // appearance.performAsCurrent 让 dynamic NSColor 在当前 effectiveAppearance 下取值
        effectiveAppearance.performAsCurrent {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            tintLayer.backgroundColor = ClaudeTheme.cream.withAlphaComponent(0.55).cgColor
            topHighlight.colors = [
                ClaudeTheme.topHighlight.cgColor,
                NSColor.white.withAlphaComponent(0).cgColor,
            ]
            bottomGlow.colors = [
                ClaudeTheme.bottomGlow.cgColor,
                NSColor.clear.cgColor,
            ]
            CATransaction.commit()
        }
    }
}

// MARK: - 外观感知容器
//
// CALayer 的 cgColor 是快照，不会随 effectiveAppearance 重算。给需要"切换明暗时
// 自动重设 layer 颜色"的 NSView 一个统一的子类，避免每个 view 都自己 override
// viewDidChangeEffectiveAppearance + 复制粘贴 refresh 逻辑。

/// 监听 effectiveAppearance 变化的轻量 NSView。
/// 把"读取动态 NSColor 并刷到 layer"的代码放到 `apply` 闭包里。
final class AppearanceAwareView: NSView {
    private let apply: (NSView) -> Void

    init(apply: @escaping (NSView) -> Void) {
        self.apply = apply
        super.init(frame: .zero)
        wantsLayer = true
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }

    private func refresh() {
        effectiveAppearance.performAsCurrent { apply(self) }
    }
}

/// 1px 分隔线，颜色用 `ClaudeTheme.hairline` 并跟随明暗。
final class AppearanceAwareDivider: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }

    private func refresh() {
        effectiveAppearance.performAsCurrent {
            layer?.backgroundColor = ClaudeTheme.hairline.cgColor
        }
    }
}

