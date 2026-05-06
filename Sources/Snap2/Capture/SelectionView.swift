import AppKit
import UniformTypeIdentifiers

/// 截图覆盖层视图。两阶段：
///   1. .selecting — 用户拖拽创建选区
///   2. .annotating — 选区已捕获，绘制标注
///
/// 不同于旧版：松手即进入标注，无确认步骤。
final class SelectionView: NSView {

    // MARK: - 状态

    private enum Mode { case selecting, annotating }
    private var mode: Mode = .selecting

    // 选区
    private var selectionRect: NSRect = .zero
    private var dragOrigin: NSPoint?
    private var isAdjusting: Bool = false   // 拖动开始与松开之间

    // 标注
    private var capturedImage: NSImage?
    /// 截图触发瞬间冻结的整屏画面；选区背景从这里取，避免动态内容被划过去
    private var frozenImage: NSImage?
    private var elements: [AnnotationElement] = []
    private var currentElement: AnnotationElement?
    private var undoStack: [[AnnotationElement]] = []

    private var currentTool: AnnotationToolType = .arrow
    private var currentColor: NSColor = AnnotationPalette.colors[0]
    private var currentLineWidth: CGFloat = LineWidthLevel.medium.rawValue

    private let toolRegistry = AnnotationToolRegistry.shared

    // 浮窗
    private var toolbarPanel: GlassPanel?
    private var toolbarView: GlassToolbar?
    private var sizeBadgePanel: GlassPanel?
    private var sizeBadgeLabel: NSTextField?

    // 内嵌文字编辑
    private weak var activeTextField: InlineAnnotationTextField?
    private var activeTextOrigin: NSPoint = .zero

    // 拖动钉图
    private var isDraggingPin: Bool = false
    /// 拖动期间幽灵预览的左下角（视图坐标）
    private var pinDragOrigin: NSPoint = .zero
    /// 鼠标按下时距选区左下角的偏移（拖动中保持指针对应原始位置）
    private var pinDragHandOffset: NSPoint = .zero
    private let pinHandleSize: CGFloat = 28
    private let pinHandleInset: CGFloat = 6
    /// 鼠标是否悬停在拖动手柄上：决定手柄绘制透明度
    private var isPinHandleHovered: Bool = false

    // MARK: - 视图设置

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // 1. 背景：有冻结画面就铺，没有则保持透明（让活的桌面透出来作降级方案）
        frozenImage?.draw(in: bounds)

        let hasSelection = selectionRect.width > 0 && selectionRect.height > 0

        // 2. 暗色蒙版
        context.saveGState()
        DrawingDefaults.overlayColor.setFill()
        if hasSelection {
            if frozenImage != nil {
                // 选区外用 even-odd 一笔覆盖，选区内保持冻结画面原色
                let mask = NSBezierPath(rect: bounds)
                mask.append(NSBezierPath(rect: selectionRect))
                mask.windingRule = .evenOdd
                mask.fill()
            } else {
                // 旧路径：先全屏蒙暗，再 clear 选区让活桌面透出
                context.fill(bounds)
                context.setBlendMode(.clear)
                context.fill(selectionRect)
            }
        } else {
            context.fill(bounds)
        }
        context.restoreGState()

        guard hasSelection else { return }

        switch mode {
        case .selecting:
            drawSelectionChrome(in: context)
        case .annotating:
            if let image = capturedImage {
                image.draw(in: selectionRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            }
            drawAnnotations(in: context)
            drawAnnotationFrame(in: context)
            drawPinHandle(in: context)
            drawPinDragGhost(in: context)
        }
    }

    /// 由 CaptureManager 在异步冻结完成后调用
    func setFrozenImage(_ image: NSImage) {
        frozenImage = image
        needsDisplay = true
    }

    /// 钉图"重新标注"入口：直接进入 annotating，跳过选区阶段。
    /// 调用方负责把钉图屏幕坐标换算为本视图局部坐标。
    func startPinEdit(image: NSImage, selectionInView rect: NSRect) {
        capturedImage = image
        selectionRect = rect
        mode = .annotating
        showAnnotationToolbar()
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    private func drawSelectionChrome(in context: CGContext) {
        // 选区边框：1px 内白 + 极轻外发光
        context.saveGState()
        NSColor.white.withAlphaComponent(0.95).setStroke()
        context.setLineWidth(1.0)
        context.stroke(selectionRect)
        context.restoreGState()

        // 8 个角/边手柄
        context.saveGState()
        for rect in handleRects {
            // 圆形手柄：白底 + 暗色内描边 + 微阴影感（用 2px stroke 形成质感）
            let path = CGPath(ellipseIn: rect, transform: nil)
            context.setShadow(offset: CGSize(width: 0, height: -1), blur: 2,
                              color: NSColor.black.withAlphaComponent(0.4).cgColor)
            context.addPath(path)
            NSColor.white.setFill()
            context.fillPath()
            context.setShadow(offset: .zero, blur: 0, color: nil)

            context.addPath(path)
            NSColor(white: 0.0, alpha: 0.25).setStroke()
            context.setLineWidth(1.0)
            context.strokePath()
        }
        context.restoreGState()
    }

    private func drawAnnotationFrame(in context: CGContext) {
        // 标注模式下，选区只画一道发光的强调色边框
        context.saveGState()
        NSColor.controlAccentColor.withAlphaComponent(0.85).setStroke()
        context.setLineWidth(1.5)
        context.stroke(selectionRect)
        context.restoreGState()
    }

    /// 选区左上角的拖动手柄（三横线 ≡）。用户从这里拖出去即新建桌面钉图。
    private func pinHandleRect() -> NSRect? {
        guard mode == .annotating, !isDraggingPin else { return nil }
        guard selectionRect.width > pinHandleSize + pinHandleInset * 2,
              selectionRect.height > pinHandleSize + pinHandleInset * 2 else { return nil }
        return NSRect(
            x: selectionRect.minX + pinHandleInset,
            y: selectionRect.maxY - pinHandleSize - pinHandleInset,
            width: pinHandleSize, height: pinHandleSize
        )
    }

    private func drawPinHandle(in context: CGContext) {
        guard let r = pinHandleRect() else { return }
        context.saveGState()
        // 默认半透明，悬停时拉满，避免常态下喧宾夺主
        context.setAlpha(isPinHandleHovered ? 1.0 : 0.35)

        // 圆角暗色背景
        let bg = CGPath(roundedRect: r, cornerWidth: 6, cornerHeight: 6, transform: nil)
        context.addPath(bg)
        NSColor.black.withAlphaComponent(0.55).setFill()
        context.fillPath()

        // 1px 白色描边突出可点击
        context.addPath(bg)
        context.setLineWidth(1)
        NSColor.white.withAlphaComponent(0.30).setStroke()
        context.strokePath()

        // 三横线（≡）
        let lineLen: CGFloat = 12
        let spacing: CGFloat = 4
        let midX = r.midX
        let midY = r.midY
        context.setLineWidth(1.5)
        context.setLineCap(.round)
        NSColor.white.withAlphaComponent(0.92).setStroke()
        for i in -1...1 {
            let y = midY + CGFloat(i) * spacing
            context.move(to: CGPoint(x: midX - lineLen / 2, y: y))
            context.addLine(to: CGPoint(x: midX + lineLen / 2, y: y))
        }
        context.strokePath()

        context.restoreGState()
    }

    /// 拖动钉图时跟随光标的幽灵预览
    private func drawPinDragGhost(in context: CGContext) {
        guard isDraggingPin, let img = capturedImage else { return }
        let rect = NSRect(origin: pinDragOrigin, size: selectionRect.size)
        img.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.85)

        context.saveGState()
        NSColor.white.withAlphaComponent(0.6).setStroke()
        context.setLineWidth(1.5)
        context.stroke(rect)
        context.restoreGState()
    }

    private func drawAnnotations(in context: CGContext) {
        context.saveGState()
        context.translateBy(x: selectionRect.origin.x, y: selectionRect.origin.y)
        for el in elements {
            toolRegistry.tool(for: el.toolType)?.draw(element: el, in: context)
        }
        if let cur = currentElement {
            toolRegistry.tool(for: cur.toolType)?.draw(element: cur, in: context)
        }
        context.restoreGState()
    }

    // MARK: - 手柄

    private let handleSize: CGFloat = 9
    private let handleHitPad: CGFloat = 6

    private var handleRects: [NSRect] {
        guard mode == .selecting, selectionRect.width > 0, selectionRect.height > 0 else { return [] }
        let r = selectionRect
        let s = handleSize
        let half = s / 2
        return [
            NSRect(x: r.minX - half, y: r.maxY - half, width: s, height: s), // 0 TL
            NSRect(x: r.maxX - half, y: r.maxY - half, width: s, height: s), // 1 TR
            NSRect(x: r.maxX - half, y: r.minY - half, width: s, height: s), // 2 BR
            NSRect(x: r.minX - half, y: r.minY - half, width: s, height: s), // 3 BL
            NSRect(x: r.midX - half, y: r.maxY - half, width: s, height: s), // 4 T
            NSRect(x: r.maxX - half, y: r.midY - half, width: s, height: s), // 5 R
            NSRect(x: r.midX - half, y: r.minY - half, width: s, height: s), // 6 B
            NSRect(x: r.minX - half, y: r.midY - half, width: s, height: s), // 7 L
        ]
    }

    private enum DragKind { case create, move, resize(Int) }
    private var dragKind: DragKind = .create
    private var moveOffset: NSPoint = .zero
    private var resizeAnchor: NSPoint = .zero

    // MARK: - 鼠标事件

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)

        if mode == .annotating {
            handleAnnotationMouseDown(p: p, event: event)
            return
        }

        // 检测命中手柄
        for (i, h) in handleRects.enumerated() {
            if h.insetBy(dx: -handleHitPad, dy: -handleHitPad).contains(p) {
                dragKind = .resize(i)
                resizeAnchor = anchorForHandle(i)
                isAdjusting = true
                return
            }
        }

        // 选区内：移动
        if selectionRect.width > 0, selectionRect.height > 0, selectionRect.contains(p) {
            dragKind = .move
            moveOffset = NSPoint(x: p.x - selectionRect.origin.x, y: p.y - selectionRect.origin.y)
            isAdjusting = true
            NSCursor.closedHand.set()
            return
        }

        // 否则：开始新建选区
        dragKind = .create
        dragOrigin = p
        selectionRect = .zero
        isAdjusting = true
        showSizeBadge()
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)

        if mode == .annotating {
            handleAnnotationMouseDragged(p: p)
            return
        }

        switch dragKind {
        case .create:
            guard let o = dragOrigin else { return }
            selectionRect = NSRect(
                x: min(o.x, p.x), y: min(o.y, p.y),
                width: abs(p.x - o.x), height: abs(p.y - o.y)
            )
        case .move:
            var origin = NSPoint(x: p.x - moveOffset.x, y: p.y - moveOffset.y)
            origin.x = max(0, min(origin.x, bounds.width - selectionRect.width))
            origin.y = max(0, min(origin.y, bounds.height - selectionRect.height))
            selectionRect.origin = origin
        case .resize(let idx):
            applyResize(handleIndex: idx, point: p)
        }

        updateSizeBadge()
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        guard mode == .annotating else { return }
        let p = convert(event.locationInWindow, from: nil)
        let nowHover = pinHandleRect()?.contains(p) ?? false
        if nowHover != isPinHandleHovered {
            isPinHandleHovered = nowHover
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        if mode == .annotating {
            handleAnnotationMouseUp(p: convert(event.locationInWindow, from: nil))
            return
        }

        // 拖动尺寸过小（<10px）视为误触，回到空选区
        let wasCreating = (selectionRect.width > 10 && selectionRect.height > 10)
        isAdjusting = false
        dragOrigin = nil
        NSCursor.crosshair.set()

        if wasCreating {
            enterAnnotationMode()
        } else {
            selectionRect = .zero
            hideSizeBadge()
            needsDisplay = true
        }
    }

    private func applyResize(handleIndex: Int, point p: NSPoint) {
        let r = selectionRect
        switch handleIndex {
        case 0...3: // 角
            selectionRect = NSRect(
                x: min(resizeAnchor.x, p.x), y: min(resizeAnchor.y, p.y),
                width: abs(p.x - resizeAnchor.x), height: abs(p.y - resizeAnchor.y)
            )
        case 4: // top
            let y = min(r.minY, p.y)
            selectionRect = NSRect(x: r.minX, y: y, width: r.width, height: abs(p.y - r.minY))
        case 5: // right
            let x = min(r.minX, p.x)
            selectionRect = NSRect(x: x, y: r.minY, width: abs(p.x - r.minX), height: r.height)
        case 6: // bottom
            let y = min(p.y, r.maxY)
            selectionRect = NSRect(x: r.minX, y: y, width: r.width, height: abs(r.maxY - p.y))
        case 7: // left
            let x = min(p.x, r.maxX)
            selectionRect = NSRect(x: x, y: r.minY, width: abs(r.maxX - p.x), height: r.height)
        default: break
        }
    }

    private func anchorForHandle(_ i: Int) -> NSPoint {
        let r = selectionRect
        switch i {
        case 0: return NSPoint(x: r.maxX, y: r.minY)
        case 1: return NSPoint(x: r.minX, y: r.minY)
        case 2: return NSPoint(x: r.minX, y: r.maxY)
        case 3: return NSPoint(x: r.maxX, y: r.maxY)
        default: return r.origin
        }
    }

    // MARK: - 键盘

    override func keyDown(with event: NSEvent) {
        // 文字输入框激活时，把按键事件让给字段（含 Cmd+S 等避免触发宿主行为）
        if activeTextField != nil {
            super.keyDown(with: event)
            return
        }

        let modifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.function, .numericPad, .capsLock])

        // ESC
        if event.keyCode == 53 {
            if mode == .annotating, currentElement != nil {
                currentElement = nil
                needsDisplay = true
                return
            }
            CaptureManager.shared.cancelCapture()
            return
        }

        // Enter → 按设置执行（复制或静默保存），并关闭
        if modifiers.isEmpty, event.keyCode == 36 || event.keyCode == 76 {
            if mode == .annotating {
                performEnterAction()
            } else if selectionRect.width > 2, selectionRect.height > 2 {
                enterAnnotationMode { [weak self] in
                    self?.performEnterAction()
                }
            }
            return
        }

        // Cmd 组合
        if modifiers.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case "z": performUndo(); return
            case "s": performSave(); return
            case "c": performCopy(); return
            case "p": performPinAtSelection(); return
            default: break
            }
        }

        // 数字键 1-6 切工具（仅标注模式）
        if mode == .annotating, modifiers.isEmpty,
           let chars = event.charactersIgnoringModifiers, chars.count == 1,
           let digit = Int(chars), digit >= 1, digit <= AnnotationToolType.allCases.count
        {
            let tool = AnnotationToolType(rawValue: digit - 1)!
            currentTool = tool
            toolbarView?.setSelectedTool(tool)
            return
        }

        super.keyDown(with: event)
    }

    // MARK: - 进入标注模式

    private func enterAnnotationMode(then completion: (() -> Void)? = nil) {
        guard let screen = window?.screen else { return }
        hideSizeBadge()

        // 优先从冻结画面裁剪——和用户实际看到的选区一致，且无需再调一次 SCK
        if let frozen = frozenImage,
           let cropped = cropFrozenImage(frozen, to: selectionRect) {
            self.capturedImage = cropped
            self.mode = .annotating
            self.showAnnotationToolbar()
            self.needsDisplay = true
            self.window?.invalidateCursorRects(for: self)
            completion?()
            return
        }

        // 降级：冻结尚未到达（用户飞快框完）或失败时重新走 SCK
        let screenFrame = screen.frame
        let captureRect = NSRect(
            x: screenFrame.origin.x + selectionRect.origin.x,
            y: screenFrame.origin.y + selectionRect.origin.y,
            width: selectionRect.width,
            height: selectionRect.height
        )
        CaptureManager.shared.captureInline(rect: captureRect, screen: screen) { [weak self] image in
            guard let self = self else { return }
            guard let image = image else {
                CaptureManager.shared.cancelCapture()
                return
            }
            self.capturedImage = image
            self.mode = .annotating
            self.showAnnotationToolbar()
            self.needsDisplay = true
            self.window?.invalidateCursorRects(for: self)
            completion?()
        }
    }

    /// 把冻结的整屏画面按选区（视图坐标，y 朝上）裁出 NSImage。
    /// CGImage 走的是顶向下坐标系，需要做 Y 翻转换算。
    private func cropFrozenImage(_ image: NSImage, to rect: NSRect) -> NSImage? {
        var proposed = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else {
            return nil
        }

        let pixelW = CGFloat(cgImage.width)
        let pixelH = CGFloat(cgImage.height)
        guard image.size.width > 0, image.size.height > 0,
              rect.width > 0, rect.height > 0 else { return nil }
        let scaleX = pixelW / image.size.width
        let scaleY = pixelH / image.size.height

        // CGImage 使用左上为原点的像素坐标；SelectionView 使用左下为原点的点坐标。
        let raw = CGRect(
            x: rect.minX * scaleX,
            y: pixelH - rect.maxY * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        )
        let minX = max(0, floor(raw.minX))
        let minY = max(0, floor(raw.minY))
        let maxX = min(pixelW, ceil(raw.maxX))
        let maxY = min(pixelH, ceil(raw.maxY))
        let cropRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)

        guard cropRect.width > 0, cropRect.height > 0,
              let cropped = cgImage.cropping(to: cropRect) else { return nil }
        return NSImage(cgImage: cropped, size: rect.size)
    }

    // MARK: - 标注鼠标

    private func handleAnnotationMouseDown(p: NSPoint, event: NSEvent) {
        // 命中拖动手柄 → 进入"拖动钉图"流程
        if let handle = pinHandleRect(), handle.contains(p) {
            isDraggingPin = true
            // 鼠标在选区中的偏移；幽灵预览原点 = 鼠标 - 偏移，保证视觉连续
            pinDragHandOffset = NSPoint(
                x: p.x - selectionRect.minX,
                y: p.y - selectionRect.minY
            )
            pinDragOrigin = NSPoint(
                x: p.x - pinDragHandOffset.x,
                y: p.y - pinDragHandOffset.y
            )
            NSCursor.closedHand.set()
            window?.invalidateCursorRects(for: self)
            needsDisplay = true
            return
        }

        guard selectionRect.contains(p) else { return }
        let local = NSPoint(x: p.x - selectionRect.origin.x,
                            y: p.y - selectionRect.origin.y)

        if currentTool == .text {
            promptText(at: local)
            return
        }

        let el = AnnotationElement(toolType: currentTool, color: currentColor, lineWidth: currentLineWidth)
        el.startPoint = local
        el.endPoint = local
        if currentTool == .freedraw { el.points.append(local) }
        currentElement = el
        needsDisplay = true
    }

    private func handleAnnotationMouseDragged(p: NSPoint) {
        if isDraggingPin {
            pinDragOrigin = NSPoint(
                x: p.x - pinDragHandOffset.x,
                y: p.y - pinDragHandOffset.y
            )
            needsDisplay = true
            return
        }

        guard let el = currentElement else { return }
        let local = NSPoint(x: p.x - selectionRect.origin.x,
                            y: p.y - selectionRect.origin.y)
        if el.toolType == .freedraw { el.points.append(local) }
        else { el.endPoint = local }
        needsDisplay = true
    }

    private func handleAnnotationMouseUp(p: NSPoint) {
        if isDraggingPin {
            commitPinDrag(at: p)
            return
        }

        guard let el = currentElement else { return }
        let local = NSPoint(x: p.x - selectionRect.origin.x,
                            y: p.y - selectionRect.origin.y)
        if el.toolType == .freedraw { el.points.append(local) }
        else { el.endPoint = local }

        if isValid(el) {
            undoStack.append(elements)
            elements.append(el)
        }
        currentElement = nil
        needsDisplay = true
    }

    /// 拖动手柄落点：以最终位置创建 PinnedImageWindow，关闭整个截图会话。
    /// 即便用户点了一下没拖（pinDragOrigin == 选区原位），也按"原位置钉图"处理。
    private func commitPinDrag(at endPoint: NSPoint) {
        guard let win = window else {
            isDraggingPin = false
            return
        }
        let dropOrigin = NSPoint(
            x: endPoint.x - pinDragHandOffset.x,
            y: endPoint.y - pinDragHandOffset.y
        )
        let screenOrigin = NSPoint(
            x: win.frame.origin.x + dropOrigin.x,
            y: win.frame.origin.y + dropOrigin.y
        )
        let image = renderFinalImage()

        isDraggingPin = false
        NSCursor.crosshair.set()
        PinnedImageWindow.show(image: image, at: screenOrigin)
        CaptureManager.shared.finishAndClose()
    }

    private func isValid(_ el: AnnotationElement) -> Bool {
        switch el.toolType {
        case .freedraw: return el.points.count >= 2
        case .text: return el.text != nil && !(el.text?.isEmpty ?? true)
        default:
            return abs(el.endPoint.x - el.startPoint.x) > 2 || abs(el.endPoint.y - el.startPoint.y) > 2
        }
    }

    /// 在选区局部坐标 `point` 处弹出内嵌文字输入框；Enter 提交，Esc 取消，失焦自动提交。
    /// 不再使用 NSAlert（在 .screenSaver 层级的 overlay 上方会被遮挡导致死锁）。
    private func promptText(at point: NSPoint) {
        finishActiveText(commit: false)

        let fontSize = max(currentLineWidth * 6, 14)
        let font = NSFont.systemFont(ofSize: fontSize)
        let lineHeight = ceil(font.boundingRectForFont.height)
        let pad: CGFloat = 6  // 与 TextTool.draw 的 textPadding 一致

        // 选区局部坐标 → 视图坐标
        let viewX = selectionRect.origin.x + point.x - pad
        let viewY = selectionRect.origin.y + point.y - pad

        let tf = InlineAnnotationTextField(frame: NSRect(
            x: viewX, y: viewY,
            width: 220, height: lineHeight + pad * 2
        ))
        tf.font = font
        tf.textColor = currentColor
        tf.backgroundColor = NSColor.black.withAlphaComponent(0.2)
        tf.drawsBackground = true
        tf.isBezeled = false
        tf.isBordered = false
        tf.placeholderString = "输入文字"
        tf.focusRingType = .none
        tf.delegate = self
        tf.wantsLayer = true
        tf.layer?.cornerRadius = 4
        tf.layer?.masksToBounds = true

        activeTextField = tf
        activeTextOrigin = point
        addSubview(tf)
        window?.makeFirstResponder(tf)
        needsDisplay = true
    }

    private func finishActiveText(commit: Bool) {
        guard let tf = activeTextField else { return }
        let text = tf.stringValue
        let origin = activeTextOrigin
        activeTextField = nil
        tf.delegate = nil
        tf.removeFromSuperview()
        // 仅在选区视图仍在响应链时回收 first responder
        if window?.firstResponder !== self {
            window?.makeFirstResponder(self)
        }

        if commit, !text.isEmpty {
            let el = AnnotationElement(toolType: .text, color: currentColor, lineWidth: currentLineWidth)
            el.startPoint = origin
            el.endPoint = origin
            el.text = text
            el.font = NSFont.systemFont(ofSize: max(currentLineWidth * 6, 14))
            undoStack.append(elements)
            elements.append(el)
        }
        needsDisplay = true
    }

    // MARK: - 操作

    private func performUndo() {
        guard mode == .annotating, let prev = undoStack.popLast() else { return }
        elements = prev
        needsDisplay = true
    }

    /// 默认 Enter 行为；按设置分流到 copy 或 silentSave
    private func performEnterAction() {
        switch EnterAction.current {
        case .copy: copyAndClose()
        case .save: silentSaveAndClose()
        }
    }

    private func performCopy() {
        if mode == .annotating { copyAndClose() }
    }

    /// ⌘S 显式带对话框保存（高级用户）
    private func performSave() {
        guard mode == .annotating else { return }
        let image = renderFinalImage()
        let (_, ext) = encode(image)
        let panel = NSSavePanel()
        panel.allowedContentTypes = ext == "jpg" ? [.jpeg] : [.png]
        panel.nameFieldStringValue = "Snap2_\(timestamp()).\(ext)"
        panel.canCreateDirectories = true
        if let dir = UserDefaults.standard.string(forKey: UDKey.saveDirectory) {
            panel.directoryURL = URL(fileURLWithPath: dir)
        }
        if panel.runModal() == .OK, let url = panel.url {
            writeImage(image, to: url)
        }
    }

    private func copyAndClose() {
        let image = renderFinalImage()
        copyImageToClipboard(image)
        CopyToast.show(image: image)
        CaptureManager.shared.finishAndClose()
    }

    /// 按设置目录+格式直接写文件，不弹任何对话框
    private func silentSaveAndClose() {
        let image = renderFinalImage()
        let (data, ext) = encode(image)
        let dir = saveDirectoryURL()
        let filename = "Snap2_\(timestamp()).\(ext)"
        let url = dir.appendingPathComponent(filename)

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: url)
            CopyToast.show(image: image,
                           message: "已保存",
                           subtitle: filename)
        } catch {
            NSLog("[Snap2] 保存失败: \(error)")
            // 保存失败兜底为复制
            copyImageToClipboard(image)
            CopyToast.show(image: image,
                           message: "保存失败，已复制到剪贴板",
                           subtitle: error.localizedDescription)
        }
        CaptureManager.shared.finishAndClose()
    }

    private func saveDirectoryURL() -> URL {
        if let dir = UserDefaults.standard.string(forKey: UDKey.saveDirectory) {
            return URL(fileURLWithPath: (dir as NSString).expandingTildeInPath)
        }
        if let desktop = NSSearchPathForDirectoriesInDomains(.desktopDirectory, .userDomainMask, true).first {
            return URL(fileURLWithPath: desktop)
        }
        return URL(fileURLWithPath: NSHomeDirectory())
    }

    private func copyImageToClipboard(_ image: NSImage) {
        let pb = NSPasteboard.general
        pb.clearContents()

        if let rep = image.representations.first as? NSBitmapImageRep {
            if let tiff = rep.tiffRepresentation {
                pb.setData(tiff, forType: .tiff)
            }
            if let png = rep.representation(using: .png, properties: [:]) {
                pb.setData(png, forType: .png)
            }
            return
        }

        if let tiff = image.tiffRepresentation {
            pb.setData(tiff, forType: .tiff)
        }
    }

    /// 按设置编码：返回 (数据, 扩展名)
    private func encode(_ image: NSImage) -> (Data, String) {
        let rep: NSBitmapImageRep?
        if let bitmap = image.representations.first as? NSBitmapImageRep {
            rep = bitmap
        } else {
            var proposed = NSRect(origin: .zero, size: image.size)
            rep = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil).map { cgImage in
                let bitmap = NSBitmapImageRep(cgImage: cgImage)
                bitmap.size = image.size
                return bitmap
            }
        }
        guard let rep else { return (Data(), "png") }

        let format = UserDefaults.standard.string(forKey: UDKey.imageFormat) ?? "png"
        if format == "jpeg" {
            let q = UserDefaults.standard.object(forKey: UDKey.jpegQuality) as? Double ?? 0.85
            let data = rep.representation(using: .jpeg, properties: [.compressionFactor: q]) ?? Data()
            return (data, "jpg")
        }
        let data = rep.representation(using: .png, properties: [:]) ?? Data()
        return (data, "png")
    }

    private func writeImage(_ image: NSImage, to url: URL) {
        let (data, _) = encode(image)
        try? data.write(to: url)
    }

    private func renderFinalImage() -> NSImage {
        guard let bg = capturedImage else { return NSImage() }

        // 逻辑尺寸来自 NSImage.size（点），像素尺寸来自原始 CGImage / rep。
        // 最终结果始终保留 backing scale：例如 200pt @2x 输出 400px。
        let pointSize = bg.size
        guard pointSize.width > 0, pointSize.height > 0 else { return NSImage() }

        var proposed = NSRect(origin: .zero, size: pointSize)
        let bgCG = bg.cgImage(forProposedRect: &proposed, context: nil, hints: nil)
        let pixelW: Int
        let pixelH: Int
        if let cg = bgCG {
            pixelW = cg.width
            pixelH = cg.height
        } else if let rep = bg.representations.first {
            pixelW = rep.pixelsWide
            pixelH = rep.pixelsHigh
        } else {
            pixelW = Int(round(pointSize.width))
            pixelH = Int(round(pointSize.height))
        }
        guard pixelW > 0, pixelH > 0 else { return NSImage() }

        guard let outRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelW, pixelsHigh: pixelH,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 32
        ) else { return NSImage() }
        outRep.size = pointSize

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let graphicsContext = NSGraphicsContext(bitmapImageRep: outRep) else { return NSImage() }
        NSGraphicsContext.current = graphicsContext
        graphicsContext.cgContext.interpolationQuality = .none

        if let cg = bgCG {
            let bgRep = NSBitmapImageRep(cgImage: cg)
            bgRep.size = pointSize
            bgRep.draw(in: NSRect(origin: .zero, size: pointSize))
        } else {
            bg.draw(in: NSRect(origin: .zero, size: pointSize),
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1.0,
                    respectFlipped: false,
                    hints: [.interpolation: NSImageInterpolation.none])
        }
        for el in elements {
            toolRegistry.tool(for: el.toolType)?.draw(element: el, in: graphicsContext.cgContext)
        }

        let result = NSImage(size: pointSize)
        result.addRepresentation(outRep)
        return result
    }

    private func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f.string(from: Date())
    }

    // MARK: - 标注玻璃工具栏

    private func showAnnotationToolbar() {
        removeToolbar()

        let toolbar = GlassToolbar(frame: .zero)
        toolbar.delegate = self
        toolbar.setSelectedTool(currentTool)
        toolbar.setSelectedColor(currentColor)
        toolbar.setSelectedWidth(LineWidthLevel.allCases.first { $0.rawValue == currentLineWidth } ?? .medium)

        let width = ceil(toolbar.intrinsicWidth())
        let height = GlassToolbar.toolbarHeight

        let panel = GlassPanel(size: NSSize(width: width, height: height))
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        panel.contentBox.addSubview(toolbar)
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: panel.contentBox.topAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: height),
            toolbar.leadingAnchor.constraint(equalTo: panel.contentBox.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: panel.contentBox.trailingAnchor),
        ])

        let target = toolbarTargetOrigin(width: panel.frame.width)
        // 入场起点：从下方 16px + 透明
        panel.setFrameOrigin(NSPoint(x: target.x, y: target.y - 16))
        panel.alphaValue = 0

        if let parent = window {
            parent.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)
        toolbarPanel = panel
        toolbarView = toolbar

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1.0
            panel.animator().setFrameOrigin(target)
        }
    }

    /// 工具栏目标原点：贴选区下沿外侧；放不下则吸附到选区内部底缘。
    /// 水平随选区中心，并钳制到 visibleFrame 内。
    private func toolbarTargetOrigin(width: CGFloat) -> NSPoint {
        guard let pw = window, let screen = pw.screen ?? NSScreen.main else { return .zero }
        let visible = screen.visibleFrame
        let height = GlassToolbar.toolbarHeight
        let gap: CGFloat = 8
        let edgeMargin: CGFloat = 8

        // 选区在屏幕坐标系中的关键点
        let so = pw.frame.origin
        let selBottomY = so.y + selectionRect.minY
        let selCenterX = so.x + selectionRect.midX

        // 水平：选区水平中心，钳到 visible 内
        var x = selCenterX - width / 2
        let minX = visible.minX + edgeMargin
        let maxX = visible.maxX - width - edgeMargin
        if maxX >= minX {
            x = max(minX, min(x, maxX))
        }

        // 垂直：默认在选区下方外侧
        var y = selBottomY - gap - height
        if y < visible.minY + edgeMargin {
            // 下方放不下（如选区贴底/全屏）：吸附到选区内部底缘
            y = selBottomY + gap
            let maxOriginY = visible.maxY - height - edgeMargin
            y = max(visible.minY + edgeMargin, min(y, maxOriginY))
        }

        return NSPoint(x: x, y: y)
    }

    private func removeToolbar() {
        if let panel = toolbarPanel {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
        toolbarPanel = nil
        toolbarView = nil
    }

    // MARK: - 玻璃尺寸徽章

    private func showSizeBadge() {
        if sizeBadgePanel != nil { return }
        let panel = GlassPanel(size: NSSize(width: 110, height: 28),
                               cornerRadius: Glass.radiusBadge)
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        label.textColor = .white
        label.backgroundColor = .clear
        label.isBezeled = false
        label.isEditable = false
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        panel.contentBox.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: panel.contentBox.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: panel.contentBox.centerYAnchor),
        ])

        if let parent = window {
            parent.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)
        sizeBadgePanel = panel
        sizeBadgeLabel = label
    }

    private func updateSizeBadge() {
        guard let panel = sizeBadgePanel, let label = sizeBadgeLabel,
              selectionRect.width > 0, selectionRect.height > 0,
              let pw = window else { return }

        let scale = pw.screen?.backingScaleFactor ?? 1.0
        let text = " \(Int(selectionRect.width * scale)) × \(Int(selectionRect.height * scale)) "
        label.stringValue = text
        label.sizeToFit()

        let w = max(110, ceil(label.frame.width) + 24)
        panel.resize(to: NSSize(width: w, height: 28))

        // 位置：选区上方居中；放不下放下面；最后再钳制到屏幕可视区
        let so = pw.frame.origin
        var x = so.x + selectionRect.midX - w / 2
        var y = so.y + selectionRect.maxY + 8
        let screenFrame = pw.screen?.frame ?? pw.frame
        if y + 28 > so.y + screenFrame.height - 8 {
            y = so.y + selectionRect.minY - 28 - 8
        }
        x = max(so.x + 8, min(x, so.x + screenFrame.width - w - 8))
        y = max(so.y + 8, min(y, so.y + screenFrame.height - 28 - 8))
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func hideSizeBadge() {
        if let panel = sizeBadgePanel {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
        sizeBadgePanel = nil
        sizeBadgeLabel = nil
    }

    // MARK: - 关闭清理

    func prepareForClose() {
        if let tf = activeTextField {
            tf.delegate = nil
            tf.removeFromSuperview()
            activeTextField = nil
        }
        removeToolbar()
        hideSizeBadge()
    }

    // MARK: - 光标

    override func resetCursorRects() {
        discardCursorRects()
        if mode == .selecting {
            if selectionRect.width > 0, selectionRect.height > 0 {
                let cursors: [NSCursor] = [
                    .resizeUpDown, .resizeUpDown, .resizeUpDown, .resizeUpDown,
                    .resizeUpDown, .resizeLeftRight, .resizeUpDown, .resizeLeftRight
                ]
                for (i, h) in handleRects.enumerated() {
                    addCursorRect(h.insetBy(dx: -handleHitPad, dy: -handleHitPad),
                                  cursor: cursors[i])
                }
                addCursorRect(selectionRect, cursor: .openHand)
            }
            addCursorRect(bounds, cursor: .crosshair)
        } else {
            addCursorRect(selectionRect, cursor: .crosshair)
            // 拖动手柄区域：抓握光标提示可拖
            if let h = pinHandleRect() {
                addCursorRect(h, cursor: .openHand)
            }
        }
    }
}

// MARK: - GlassToolbarDelegate

extension SelectionView: GlassToolbarDelegate {
    func toolbarDidPickTool(_ tool: AnnotationToolType) {
        currentTool = tool
    }
    func toolbarDidPickColor(_ color: NSColor) {
        currentColor = color
    }
    func toolbarDidPickWidth(_ width: CGFloat) {
        currentLineWidth = width
    }
    func toolbarDidTapUndo() { performUndo() }
    func toolbarDidTapSave() { performSave() }
    func toolbarDidTapCopy() { copyAndClose() }
    func toolbarDidTapPin()  { performPinAtSelection() }
    func toolbarDidTapClose() { CaptureManager.shared.cancelCapture() }

    /// 工具栏点击或 ⌘P 触发：在选区原位置创建一张钉图，并结束本次截图会话
    private func performPinAtSelection() {
        guard mode == .annotating, let win = window else { return }
        let image = renderFinalImage()
        let screenOrigin = NSPoint(
            x: win.frame.origin.x + selectionRect.origin.x,
            y: win.frame.origin.y + selectionRect.origin.y
        )
        PinnedImageWindow.show(image: image, at: screenOrigin)
        CaptureManager.shared.finishAndClose()
    }
}

// MARK: - 内嵌文字输入

/// 标注文字输入框。继承 NSTextField 仅为给类型加身份标识，便于在 SelectionView 引用。
final class InlineAnnotationTextField: NSTextField {}

extension SelectionView: NSTextFieldDelegate {
    /// 拦截 Esc / Enter，分别走取消与提交。
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.cancelOperation(_:)):
            finishActiveText(commit: false)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            finishActiveText(commit: true)
            return true
        default:
            return false
        }
    }

    /// 失焦自动提交（点击工具栏切工具、点别的位置等）。
    func controlTextDidEndEditing(_ obj: Notification) {
        finishActiveText(commit: true)
    }
}
