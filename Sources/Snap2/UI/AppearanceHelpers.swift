import AppKit

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
        effectiveAppearance.performAsCurrentDrawingAppearance { apply(self) }
    }
}

/// 1px 分隔线，颜色用系统 `separatorColor` 并跟随明暗。
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
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.separatorColor.cgColor
        }
    }
}
