import AppKit

// MARK: - 文字标注工具

/// 在指定位置绘制文字，带模糊磨砂背景。
///
/// 背景：标注位置背后常有原文/密集 UI，纯半透明底压不住。draw 时若 element 带有
/// blurSource（整张选区背景的预高斯模糊图，SelectionView 创建元素时注入并缓存），
/// 则从其中裁出文字背后区域画成磨砂底，再叠一层半透明黑 tint 保证对比度；
/// 没有 blurSource（老会话/降级路径）时退回纯半透明黑底。
struct TextTool: AnnotationTool {
    let toolType: AnnotationToolType = .text

    /// 文字内边距（与 SelectionView.promptText 的 pad 保持一致）
    static let textPadding: CGFloat = 6.0
    /// 背景圆角半径
    static let cornerRadius: CGFloat = 4.0
    /// 背景透明度
    static let backgroundAlpha: CGFloat = 0.2

    /// 元素缺 font 时的兜底字号（正常路径 SelectionView 都会带 font）
    private static let fallbackFontSize: CGFloat = 16

    // MARK: 共享几何（绘制与命中测试同源，避免两处公式漂移）

    static func font(for element: AnnotationElement) -> NSFont {
        element.font ?? NSFont.systemFont(ofSize: fallbackFontSize)
    }

    static func textSize(for element: AnnotationElement) -> NSSize {
        guard let text = element.text, !text.isEmpty else { return .zero }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font(for: element),
            .foregroundColor: NSColor.black
        ]
        return NSAttributedString(string: text, attributes: attributes).size()
    }

    /// 文字背景矩形（含内边距，选区局部坐标，y 朝上）。
    /// startPoint 是"文字块左下角"语义（与 promptText 摆放输入框的公式一致）。
    static func backgroundRect(for element: AnnotationElement) -> NSRect {
        let size = textSize(for: element)
        return NSRect(
            x: element.startPoint.x - textPadding,
            y: element.startPoint.y - textPadding,
            width: size.width + textPadding * 2,
            height: size.height + textPadding * 2
        )
    }

    /// 从"整张选区"的源图（点尺寸 pointSize）中裁出选区局部 rect 的像素区域。
    /// CGImage 像素坐标顶向下，视图坐标 y 朝上，需做 Y 翻转（与 MosaicTool 同一套换算）。
    static func cropSource(_ source: CGImage, pointSize: NSSize, to rect: NSRect) -> CGImage? {
        guard pointSize.width > 0, pointSize.height > 0,
              rect.width > 0, rect.height > 0 else { return nil }
        let scale = CGFloat(source.width) / pointSize.width
        let imgX = max(0, round(rect.minX * scale))
        let imgY = max(0, round((pointSize.height - rect.maxY) * scale))
        let clampedW = min(round(rect.width * scale), CGFloat(source.width) - imgX)
        let clampedH = min(round(rect.height * scale), CGFloat(source.height) - imgY)
        guard clampedW > 0, clampedH > 0 else { return nil }
        return source.cropping(to: CGRect(x: imgX, y: imgY, width: clampedW, height: clampedH))
    }

    func draw(element: AnnotationElement, in context: CGContext) {
        guard let text = element.text, !text.isEmpty else { return }

        let font = TextTool.font(for: element)
        let position = element.startPoint
        let backgroundRect = TextTool.backgroundRect(for: element)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: element.color
        ]
        let attributedString = NSAttributedString(string: text, attributes: attributes)

        context.saveGState()
        // 背景：优先磨砂（模糊裁剪），否则退回半透明黑。clip 只作用于背景层。
        let bgPath = CGPath(roundedRect: backgroundRect,
                            cornerWidth: TextTool.cornerRadius,
                            cornerHeight: TextTool.cornerRadius, transform: nil)
        context.addPath(bgPath)
        context.clip()
        if let blurSource = element.blurSource,
           let crop = TextTool.cropSource(blurSource,
                                          pointSize: element.blurSourceSize,
                                          to: backgroundRect) {
            // 裁剪图与目标矩形同尺寸，无需插值
            context.interpolationQuality = .none
            context.draw(crop, in: backgroundRect)
        }
        // tint 层：磨砂/纯色路径都叠，保证文字与任意背景的对比度
        NSColor.black.withAlphaComponent(TextTool.backgroundAlpha).setFill()
        context.fill(backgroundRect)
        context.restoreGState()

        // 绘制文字（使用 NSAttributedString 绘制）。
        // 放在 clip 之外——字形 descender 可能探出背景矩形底缘，圆角裁剪会把它们切掉。
        // 需要在 NSGraphicsContext 中绘制
        NSGraphicsContext.saveGraphicsState()
        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current = nsContext
        attributedString.draw(at: position)
        NSGraphicsContext.restoreGraphicsState()
    }

    func createPath(from startPoint: NSPoint, to endPoint: NSPoint) -> NSBezierPath {
        // 文字工具的路径是文字位置的一个标记点
        let path = NSBezierPath()
        let markerRect = NSRect(x: startPoint.x - 2, y: startPoint.y - 2, width: 4, height: 4)
        path.appendOval(in: markerRect)
        return path
    }
}
