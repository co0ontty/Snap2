import AppKit

// MARK: - 马赛克标注工具

/// 把选区底图按矩形区域像素化（打码）。
///
/// 工作方式：
/// - element.mosaicSource 是"整张选区背景"的预 pixelate CGImage（由 SelectionView 在创建
///   element 时按当前线宽注入并缓存），其逻辑尺寸（点）= element.mosaicSourceSize = 选区点尺寸。
/// - 绘制时根据 startPoint / endPoint 算出矩形（选区局部点坐标），从源图中按像素裁出对应
///   区域，再绘制到目标矩形上。CGImage.cropping 是 O(1)，每帧拖拽都很轻。
///
/// 注：mosaic 不使用 element.color；element.lineWidth 在 SelectionView 那边映射为块大小。
struct MosaicTool: AnnotationTool {
    let toolType: AnnotationToolType = .mosaic

    func draw(element: AnnotationElement, in context: CGContext) {
        guard let source = element.mosaicSource else { return }
        let pointSize = element.mosaicSourceSize
        guard pointSize.width > 0, pointSize.height > 0 else { return }

        let rect = NSRect(
            x: min(element.startPoint.x, element.endPoint.x),
            y: min(element.startPoint.y, element.endPoint.y),
            width: abs(element.endPoint.x - element.startPoint.x),
            height: abs(element.endPoint.y - element.startPoint.y)
        )
        guard rect.width > 1, rect.height > 1 else { return }

        // 点 → 像素 缩放
        let scale = CGFloat(source.width) / pointSize.width

        // CGImage 像素坐标顶向下；视图坐标 y 朝上。
        // rect.maxY（视图顶部）→ 像素 y = (pointSize.height - rect.maxY) * scale
        let imgX = max(0, round(rect.minX * scale))
        let imgY = max(0, round((pointSize.height - rect.maxY) * scale))
        let imgW = round(rect.width * scale)
        let imgH = round(rect.height * scale)
        let clampedW = min(imgW, CGFloat(source.width) - imgX)
        let clampedH = min(imgH, CGFloat(source.height) - imgY)
        guard clampedW > 0, clampedH > 0,
              let cropped = source.cropping(to: CGRect(x: imgX, y: imgY,
                                                       width: clampedW, height: clampedH))
        else { return }

        context.saveGState()
        // 块状像素再被双线性插值会糊掉，关闭插值。
        context.interpolationQuality = .none
        context.draw(cropped, in: rect)
        context.restoreGState()
    }
}
