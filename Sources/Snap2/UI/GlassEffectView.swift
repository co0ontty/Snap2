import AppKit
import QuartzCore

/// 液态玻璃容器视图。
///
/// 渲染层栈（从下到上）：
/// 1. NSVisualEffectView (.hudWindow / behindWindow) ── 模糊背景
/// 2. tintLayer ── 极轻的暗色调，确保白色高光可见
/// 3. highlightLayer ── 顶部到 50% 处的白色渐变高光（玻璃反光）
/// 4. bottomGlowLayer ── 底部边缘的反光线
/// 5. innerStrokeLayer ── 1px 内描边（玻璃边缘）
/// 6. contentView ── 子视图载入区
final class GlassEffectView: NSView {

    let contentView = NSView()

    private let blurView = NSVisualEffectView()
    private let tintLayer = CALayer()
    private let highlightLayer = CAGradientLayer()
    private let bottomGlowLayer = CAGradientLayer()
    private let innerStrokeLayer = CAShapeLayer()

    var cornerRadius: CGFloat = Glass.radiusToolbar {
        didSet { layoutLayers() }
    }

    /// 可选：染色叠加（用于强调色 tint，如选中态卡片）
    var tintColor: NSColor? {
        didSet { layoutLayers() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.masksToBounds = true

        blurView.material = .hudWindow
        blurView.blendingMode = .behindWindow
        blurView.state = .active
        blurView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurView)

        // 加载层级
        if let layer = layer {
            layer.addSublayer(tintLayer)
            layer.addSublayer(highlightLayer)
            layer.addSublayer(bottomGlowLayer)
            layer.addSublayer(innerStrokeLayer)
        }

        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)

        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        configureLayers()
    }

    private func configureLayers() {
        // 顶部 → 中部白色渐变（玻璃反光）
        highlightLayer.colors = [
            Glass.topHighlight.cgColor,
            Glass.topHighlightFade.cgColor,
        ]
        highlightLayer.startPoint = CGPoint(x: 0.5, y: 1.0)
        highlightLayer.endPoint = CGPoint(x: 0.5, y: 0.45)
        highlightLayer.locations = [0.0, 1.0]

        // 底部 1px 反光线
        bottomGlowLayer.colors = [
            NSColor.white.withAlphaComponent(0.0).cgColor,
            NSColor.white.withAlphaComponent(0.10).cgColor,
        ]
        bottomGlowLayer.startPoint = CGPoint(x: 0.5, y: 1.0)
        bottomGlowLayer.endPoint = CGPoint(x: 0.5, y: 0.0)
        bottomGlowLayer.locations = [0.92, 1.0]

        // 1px 内描边
        innerStrokeLayer.fillColor = .clear
        innerStrokeLayer.strokeColor = Glass.strokeColor.cgColor
        innerStrokeLayer.lineWidth = Glass.strokeWidth
    }

    override func layout() {
        super.layout()
        layoutLayers()
    }

    private func layoutLayers() {
        guard layer != nil else { return }
        layer?.cornerRadius = cornerRadius

        let r = bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        tintLayer.frame = r
        if let tint = tintColor {
            tintLayer.backgroundColor = tint.withAlphaComponent(0.18).cgColor
        } else {
            tintLayer.backgroundColor = NSColor.black.withAlphaComponent(0.10).cgColor
        }

        highlightLayer.frame = r
        bottomGlowLayer.frame = r

        // 内描边沿圆角矩形走（缩进 0.5px 让 1px 描边落在内）
        let inset: CGFloat = Glass.strokeWidth / 2
        let strokeRect = r.insetBy(dx: inset, dy: inset)
        innerStrokeLayer.path = CGPath(roundedRect: strokeRect,
                                       cornerWidth: max(0, cornerRadius - inset),
                                       cornerHeight: max(0, cornerRadius - inset),
                                       transform: nil)
        CATransaction.commit()
    }

}
