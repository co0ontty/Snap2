import AppKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers

/// 截图覆盖层视图。两阶段：
///   1. .selecting — 用户拖拽创建选区
///   2. .annotating — 选区已捕获，绘制标注
///
/// 不同于旧版：松手即进入标注，无确认步骤。进入标注后仍可微调选区——
/// 角/边小圆点拖拽 resize，选区外侧 12px 一圈拖拽 move（光标会变 openHand 提示）。
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
    /// capturedImage 对应的原始像素 CGImage，单独持有用于像素级操作。
    /// 不再走 NSImage.cgImage(forProposedRect:) round-trip——那条路径在某些机型/版本上
    /// 会把高分图按 proposedRect（点尺寸）重采样回点级分辨率，导致输出"分辨率特别低"
    /// 且伴随插值模糊的"抖动"感。
    private var capturedCGImage: CGImage?
    /// 截图触发瞬间冻结的整屏画面；选区背景从这里取，避免动态内容被划过去
    private var frozenImage: NSImage?
    /// frozenImage 对应的原始像素 CGImage，理由同 capturedCGImage
    private var frozenCGImage: CGImage?
    private var elements: [AnnotationElement] = []
    private var currentElement: AnnotationElement?
    private var undoStack: [[AnnotationElement]] = []

    /// 马赛克源图缓存：key = 块大小（像素，整数化避免浮点 key 抖动），value = pre-pixelated 整图
    private var mosaicCache: [Int: CGImage] = [:]
    /// 复用的 CIContext（开销大，避免每次新建）
    private static let mosaicCIContext = CIContext()

    /// 工具 / 颜色 / 线宽都从 UserDefaults 恢复上次会话的选择。
    private var currentTool: AnnotationToolType = AnnotationPreferences.loadTool()
    private var currentColor: NSColor = AnnotationPreferences.loadColor()
    private var currentLineWidth: CGFloat = AnnotationPreferences.loadLineWidth().rawValue

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

    // 标注模式下调整选区位置/大小
    // 设计：保留团队 "松手即进入标注" 的 fast path 不变，只在标注模式里追加可调能力——
    //   resize：8 个小尺寸控制点（角 + 边中点）
    //   move  ：选区外侧 12px 隐形 ring（光标变 openHand 提示可拖）
    // 选区改变后，从 frozenCGImage 重新裁 capturedCGImage，让最终输出与新选区一致。
    private enum SelectionAdjust {
        case resizing(Int)  // 0..7，与 handleRects 编号一致
        case moving
    }
    private var selectionAdjust: SelectionAdjust?
    /// move 时鼠标相对 selectionRect.origin 的偏移。
    /// resize 复用 .selecting 模式的 resizeAnchor 属性（两模式 anchor 语义相同，
    /// 且不会同时活跃，可安全共用以避免 applyResize 跨字段读取）。
    private var selectionAdjustMoveOffset: NSPoint = .zero
    /// move ring 宽度（在选区外侧）
    private let annotationMoveRingWidth: CGFloat = 12
    /// 标注模式下的小型 resize 控制点尺寸（圆点直径）和命中扩展
    private let annotationHandleSize: CGFloat = 8
    private let annotationHandleHitPad: CGFloat = 6

    // MARK: - 视图设置

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func makeBackingLayer() -> CALayer {
        // backing store 的色彩空间由 OverlayWindow.colorSpace（P3）决定，
        // CALayer 公共 API 没有 colorspace 属性，无需也不能在这里再设一次。
        return super.makeBackingLayer()
    }

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
            // 有冻结底图时，选区内容已由 step 1 的 frozenImage.draw(in: bounds) 提供：
            // frozenImage 按 1:1（image.size == bounds.size）铺满视图，选区对应区域的像素
            // 原样保留（未被 even-odd 蒙版覆盖），直接在其上叠标注即可。
            //
            // 不再用 capturedImage 重画选区背景——capturedImage 经过 crop + round，
            // 与 selectionRect（浮点拖拽坐标）存在微小 size 差异，NSImage.draw 会做
            // 轻微缩放 + 双线性插值，正是「松手一瞬间变模糊」的根因。
            //
            // 无冻结（editPin / 降级路径）时才用 capturedImage 填充背景。
            if frozenImage == nil, let image = capturedImage {
                image.draw(in: selectionRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            }
            drawAnnotations(in: context)
            drawAnnotationFrame(in: context)
            drawPinHandle(in: context)
            drawPinDragGhost(in: context)
        }
    }

    /// 由 CaptureManager 在异步冻结完成后调用。
    /// 同时持有 NSImage（供 draw_in 直接绘制）和 CGImage（供后续像素级 crop）。
    func setFrozenSnapshot(cgImage: CGImage, pointSize: NSSize) {
        frozenCGImage = cgImage
        frozenImage = NSImage(cgImage: cgImage, size: pointSize)
        needsDisplay = true
    }

    /// 钉图"重新标注"入口：直接进入 annotating，跳过选区阶段。
    /// 调用方负责把钉图屏幕坐标换算为本视图局部坐标，并尽量把原始 CGImage 一并提供，
    /// 这样 renderFinalImage 能跳过 NSImage round-trip 保住高分输出。
    /// - Parameter startTool: 从钉图 hover 工具栏点哪个工具进入就传哪个；nil 时保持上次工具。
    func startPinEdit(image: NSImage,
                      cgImage: CGImage?,
                      selectionInView rect: NSRect,
                      startTool: AnnotationToolType? = nil)
    {
        capturedImage = image
        capturedCGImage = cgImage
        mosaicCache.removeAll()
        selectionRect = rect
        mode = .annotating
        if let tool = startTool {
            currentTool = tool
        }
        showAnnotationToolbar()
        // showAnnotationToolbar 内部从 currentTool 创建工具栏并 setSelectedTool，
        // 所以 currentTool 已设过的话工具栏会自动同步到那个工具。
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
        ClaudeTheme.accent.withAlphaComponent(0.85).setStroke()
        context.setLineWidth(1.5)
        context.stroke(selectionRect)
        context.restoreGState()

        drawAnnotationResizeHandles(in: context)
    }

    /// 标注模式下的小型 resize 控制点：白色小圆点 + 1px 强调色描边。
    /// 故意比 .selecting 模式的 9px 大手柄更克制，避免在画注释时喧宾夺主。
    /// editPin 路径无 frozenCGImage，resize 会导致 NSImage.draw 缩放变形——故隐藏控制点。
    private func drawAnnotationResizeHandles(in context: CGContext) {
        guard !isDraggingPin, frozenCGImage != nil else { return }
        let rects = annotationResizeHandleRects
        guard !rects.isEmpty else { return }

        context.saveGState()
        for r in rects {
            let path = CGPath(ellipseIn: r, transform: nil)
            // 阴影让圆点在任意背景上都看得见，但比 .selecting 手柄更浅
            context.setShadow(offset: CGSize(width: 0, height: -1), blur: 1.5,
                              color: NSColor.black.withAlphaComponent(0.35).cgColor)
            context.addPath(path)
            NSColor.white.setFill()
            context.fillPath()
            context.setShadow(offset: .zero, blur: 0, color: nil)

            context.addPath(path)
            ClaudeTheme.accent.withAlphaComponent(0.85).setStroke()
            context.setLineWidth(1.0)
            context.strokePath()
        }
        context.restoreGState()
    }

    /// 标注模式下的 8 个 resize 控制点位置。
    /// 编号与 .selecting 模式的 handleRects 完全一致，复用 applyResize / anchorForHandle。
    /// 选区过小（容纳不下手柄）时返回空数组，避免视觉拥挤。
    private var annotationResizeHandleRects: [NSRect] {
        guard mode == .annotating, frozenCGImage != nil,
              selectionRect.width > annotationHandleSize * 3,
              selectionRect.height > annotationHandleSize * 3 else { return [] }
        let r = selectionRect
        let s = annotationHandleSize
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

    /// 命中测试：返回点击到了哪个 resize 控制点（0..7），否则返回 nil。
    /// 已加上 hit-pad，比视觉尺寸更宽容。
    private func hitTestAnnotationHandle(_ p: NSPoint) -> Int? {
        for (i, h) in annotationResizeHandleRects.enumerated() {
            if h.insetBy(dx: -annotationHandleHitPad, dy: -annotationHandleHitPad).contains(p) {
                return i
            }
        }
        return nil
    }

    /// 命中测试：点是否落在"选区外侧 ring"（move 区）。
    /// 必须 ① 不在选区内 ② 在选区外侧 ring 内 ③ 没有被 resize 控制点抢先命中。
    /// editPin 模式下 frozenCGImage 为空，也允许 move（capturedImage 会跟随 selectionRect 走）。
    private func hitTestAnnotationMoveRing(_ p: NSPoint) -> Bool {
        guard selectionRect.width > 0, selectionRect.height > 0 else { return false }
        if selectionRect.contains(p) { return false }
        let outer = selectionRect.insetBy(dx: -annotationMoveRingWidth, dy: -annotationMoveRingWidth)
        if !outer.contains(p) { return false }
        if hitTestAnnotationHandle(p) != nil { return false }
        return true
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
        // 默认 0.6 让用户即便不 hover 也能看见可拖动手柄；悬停时拉满。
        // 旧值 0.35 在浅色截图上几乎看不见，新用户不知道"还能拖出去钉到桌面"。
        context.setAlpha(isPinHandleHovered ? 1.0 : 0.6)

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
        let modifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.function, .numericPad, .capsLock])

        // 文字输入框激活时：
        //   - 普通按键 / ⌘Z       → 让给字段（输入文字 / 字段自己的 undo）
        //   - ⌘S / ⌘C / ⌘P 等   → 提交当前文字后转到外层动作
        // 这样在编辑时仍能"保存截图 / 复制 / 钉桌面"，但不会把 ⌘Z 解释成"撤销前一个箭头"
        // 而让正在输入的文字蒸发掉。
        if activeTextField != nil {
            let isExitAction = modifiers.contains(.command) &&
                event.charactersIgnoringModifiers.map({ ["s", "c", "p"].contains($0) }) == true
            if isExitAction {
                finishActiveText(commit: true)
                // 接着 fallthrough 到下面的 Cmd 分支
            } else {
                super.keyDown(with: event)
                return
            }
        }

        // ESC：分级取消
        //   1) 正在拖一个 element（鼠标按下未抬起）→ 仅丢弃当前元素
        //   2) 标注模式有历史元素 → 撤销最近一个（等价于 ⌘Z）
        //   3) 否则                → 关掉整次截图
        if event.keyCode == 53 {
            if mode == .annotating, currentElement != nil {
                currentElement = nil
                needsDisplay = true
                return
            }
            if mode == .annotating, !elements.isEmpty {
                performUndo()
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

        // 数字键 1-N 切工具（仅标注模式）。N = AnnotationToolType.allCases.count，
        // 当前为 7：箭头/矩形/椭圆/画笔/文字/高亮/马赛克。
        if mode == .annotating, modifiers.isEmpty,
           let chars = event.charactersIgnoringModifiers, chars.count == 1,
           let digit = Int(chars), digit >= 1, digit <= AnnotationToolType.allCases.count
        {
            let tool = AnnotationToolType(rawValue: digit - 1)!
            currentTool = tool
            AnnotationPreferences.saveTool(tool)
            toolbarView?.setSelectedTool(tool)
            return
        }

        super.keyDown(with: event)
    }

    // MARK: - 进入标注模式

    private func enterAnnotationMode(then completion: (() -> Void)? = nil) {
        guard let screen = window?.screen else { return }
        hideSizeBadge()

        // 直接尝试一次冻结裁剪
        if tryCropFrozenAndEnterAnnotating(completion: completion) {
            return
        }

        // 冻结尚未到达（用户飞快框完）—— 短暂等待最多 ~250 ms 让 SCK 全屏冻结到位，
        // 避免直接降级走 captureInline：那条路径会让用户看到 overlay 短暂"延迟一帧"
        // 的画面（暗色蒙版还在屏上时再发一次 SCK 抓取）。
        pollFrozenWithDeadline(remainingTries: 5, screen: screen, completion: completion)
    }

    /// 检查 frozenCGImage 是否已就绪；就绪则直接裁出 captured 并切到 annotating。
    /// 返回 true 表示成功进入 annotating。
    /// - 若窗口已不存在（用户在 polling 期间按了 Esc），返回 true 终止 polling 链，
    ///   避免在已 detach 的 view 上继续操作。
    private func tryCropFrozenAndEnterAnnotating(completion: (() -> Void)?) -> Bool {
        guard window != nil else { return true }
        guard let frozenCG = frozenCGImage,
              let frozenSize = frozenImage?.size,
              let cropped = cropFrozenCGImage(frozenCG, frozenPointSize: frozenSize, to: selectionRect)
        else { return false }

        self.capturedCGImage = cropped.cgImage
        self.capturedImage = NSImage(cgImage: cropped.cgImage, size: cropped.pointSize)
        self.mosaicCache.removeAll()
        self.mode = .annotating
        self.showAnnotationToolbar()
        self.needsDisplay = true
        self.window?.invalidateCursorRects(for: self)
        completion?()
        return true
    }

    /// 轮询 frozenCGImage 是否到达，每 50 ms 一次，最多 remainingTries 次。
    /// 超过预算仍未到则降级走 captureInline。
    private func pollFrozenWithDeadline(remainingTries: Int,
                                        screen: NSScreen,
                                        completion: (() -> Void)?)
    {
        if remainingTries <= 0 {
            fallbackToCaptureInline(screen: screen, completion: completion)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.050) { [weak self] in
            guard let self = self else { return }
            if self.tryCropFrozenAndEnterAnnotating(completion: completion) { return }
            self.pollFrozenWithDeadline(remainingTries: remainingTries - 1,
                                        screen: screen,
                                        completion: completion)
        }
    }

    /// 等不到冻结时的兜底：在 overlay 上直接发 SCK 截图（旧路径）。
    private func fallbackToCaptureInline(screen: NSScreen, completion: (() -> Void)?) {
        // polling 期间用户可能已 Esc 关掉 overlay
        guard window != nil else { return }
        let screenFrame = screen.frame
        let captureRect = NSRect(
            x: screenFrame.origin.x + selectionRect.origin.x,
            y: screenFrame.origin.y + selectionRect.origin.y,
            width: selectionRect.width,
            height: selectionRect.height
        )
        CaptureManager.shared.captureInline(rect: captureRect, screen: screen) { [weak self] cgImage, pointSize in
            guard let self = self else { return }
            guard let cgImage = cgImage else {
                CaptureManager.shared.cancelCapture()
                return
            }
            self.capturedCGImage = cgImage
            self.capturedImage = NSImage(cgImage: cgImage, size: pointSize)
            self.mosaicCache.removeAll()
            self.mode = .annotating
            self.showAnnotationToolbar()
            self.needsDisplay = true
            self.window?.invalidateCursorRects(for: self)
            completion?()
        }
    }

    /// 把冻结的整屏画面按选区（视图坐标，y 朝上）裁出 CGImage。
    /// CGImage 走的是顶向下坐标系，需要做 Y 翻转换算。
    /// 直接对 CGImage 操作，绕开 NSImage.cgImage(forProposedRect:) 的有损 round-trip。
    private func cropFrozenCGImage(_ cgImage: CGImage, frozenPointSize: NSSize, to rect: NSRect) -> (cgImage: CGImage, pointSize: NSSize)? {
        let pixelW = CGFloat(cgImage.width)
        let pixelH = CGFloat(cgImage.height)
        guard frozenPointSize.width > 0, frozenPointSize.height > 0,
              rect.width > 0, rect.height > 0 else { return nil }
        let scaleX = pixelW / frozenPointSize.width
        let scaleY = pixelH / frozenPointSize.height

        // 用 round 而不是 floor/ceil，避免 cropped 像素尺寸与 NSImage.size 的比例
        // 偏离 backingScale，从而让 renderFinalImage 中的 1:1 像素绘制出现非整数缩放
        // 而看起来"模糊"。
        let originX = max(0, round(rect.minX * scaleX))
        let originY = max(0, round((frozenPointSize.height - rect.maxY) * scaleY))
        let widthPx = round(rect.width * scaleX)
        let heightPx = round(rect.height * scaleY)
        let clampedW = min(widthPx, pixelW - originX)
        let clampedH = min(heightPx, pixelH - originY)
        guard clampedW > 0, clampedH > 0 else { return nil }
        let cropRect = CGRect(x: originX, y: originY, width: clampedW, height: clampedH)

        guard let cropped = cgImage.cropping(to: cropRect) else { return nil }
        // pointSize 严格 = 像素 / scale，保证后续 renderFinalImage 里 pixel:point 比例
        // 恒等于 backing scale。
        let pointSize = NSSize(width: clampedW / scaleX, height: clampedH / scaleY)
        return (cropped, pointSize)
    }

    // MARK: - 马赛克源生成

    /// 把当前选区背景按"线宽 → 块大小"映射做一次 CIPixellate，并按块大小缓存整图。
    /// 同一线宽多次创建 mosaic element 共享同一份 CGImage，CGImage.cropping 是 O(1)。
    private func ensureMosaicSource(forLineWidth lineWidth: CGFloat) -> CGImage? {
        guard let cgSource = capturedCGImage,
              let pointSize = capturedImage?.size,
              pointSize.width > 0, pointSize.height > 0 else { return nil }

        // 像素分辨率与点尺寸的比例（≈ backingScale）
        let scale = CGFloat(cgSource.width) / pointSize.width
        // 线宽 → 块大小：thin/medium/thick = 1.5/3.0/5.5 → 约 8/15/27 点
        let blockPoints = max(6, round(lineWidth * 5))
        let blockPixels = max(2, blockPoints * scale)
        let key = Int(blockPixels.rounded())

        if let cached = mosaicCache[key] { return cached }

        let ci = CIImage(cgImage: cgSource)
        guard let filter = CIFilter(name: "CIPixellate") else { return nil }
        filter.setValue(ci, forKey: kCIInputImageKey)
        // inputCenter 决定块网格对齐，用图像中心即可
        filter.setValue(CIVector(x: ci.extent.midX, y: ci.extent.midY), forKey: kCIInputCenterKey)
        filter.setValue(blockPixels, forKey: kCIInputScaleKey)
        guard let output = filter.outputImage,
              let baked = Self.mosaicCIContext.createCGImage(output, from: ci.extent) else {
            return nil
        }
        mosaicCache[key] = baked
        return baked
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

        // 命中 resize 控制点 → 调整选区大小（顺序：先于 move ring，hit-pad 已覆盖角点附近）
        if let idx = hitTestAnnotationHandle(p) {
            selectionAdjust = .resizing(idx)
            resizeAnchor = anchorForHandle(idx)  // applyResize 直接读取此字段
            // 不再 removeToolbar——工具栏跟随选区移动（commitSelectionAdjust 重排位置），
            // 避免每次微调都看到工具栏淡入淡出闪烁。
            showSizeBadge()
            updateSizeBadge()
            return
        }

        // 命中外侧 move ring → 移动整个选区（选区内部仍为标注绘制保留）
        if hitTestAnnotationMoveRing(p) {
            selectionAdjust = .moving
            selectionAdjustMoveOffset = NSPoint(
                x: p.x - selectionRect.origin.x,
                y: p.y - selectionRect.origin.y
            )
            NSCursor.closedHand.set()
            showSizeBadge()
            updateSizeBadge()
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
        if currentTool == .mosaic {
            el.mosaicSource = ensureMosaicSource(forLineWidth: currentLineWidth)
            el.mosaicSourceSize = capturedImage?.size ?? .zero
        }
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

        if let adjust = selectionAdjust {
            switch adjust {
            case .resizing(let idx):
                applyResize(handleIndex: idx, point: p)
            case .moving:
                var origin = NSPoint(
                    x: p.x - selectionAdjustMoveOffset.x,
                    y: p.y - selectionAdjustMoveOffset.y
                )
                // clamp 到 bounds，避免选区被拖出屏幕外不可恢复
                origin.x = max(0, min(origin.x, bounds.width - selectionRect.width))
                origin.y = max(0, min(origin.y, bounds.height - selectionRect.height))
                selectionRect.origin = origin
            }
            updateSizeBadge()
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
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

        if selectionAdjust != nil {
            commitSelectionAdjust()
            return
        }

        guard let el = currentElement else { return }
        let local = NSPoint(x: p.x - selectionRect.origin.x,
                            y: p.y - selectionRect.origin.y)
        if el.toolType == .freedraw { el.points.append(local) }
        else { el.endPoint = local }

        if isValid(el) {
            pushUndoSnapshot()
            elements.append(el)
        }
        currentElement = nil
        needsDisplay = true
    }

    /// 把当前 elements 的深拷贝快照压入 undoStack。
    /// 不直接 append elements——AnnotationElement 是 class，浅拷贝数组会与未来修改
    /// 共享同一份 element 引用，潜在让旧版本回灌新字段。
    private func pushUndoSnapshot() {
        undoStack.append(elements.map { $0.copy() })
    }

    /// 标注模式下 resize / move 结束：
    /// 1. 用新 selectionRect 从 frozenCGImage 重新裁出 capturedCGImage（高分原图）
    /// 2. 失效 mosaicCache（源图变了，旧像素化样本不能再用）
    /// 3. 重排玻璃工具栏到新选区下方
    /// editPin 路径无 frozenCGImage——这条路径里只允许 move（resize 控制点被隐藏），
    /// 且 capturedImage 会在 draw 阶段按当前 selectionRect 自动跟随，无需重裁。
    private func commitSelectionAdjust() {
        selectionAdjust = nil
        hideSizeBadge()

        if let frozenCG = frozenCGImage,
           let frozenSize = frozenImage?.size,
           let cropped = cropFrozenCGImage(frozenCG, frozenPointSize: frozenSize, to: selectionRect) {
            capturedCGImage = cropped.cgImage
            capturedImage = NSImage(cgImage: cropped.cgImage, size: cropped.pointSize)
            mosaicCache.removeAll()
        }
        // editPin 路径（frozenCGImage == nil）此处不重裁——capturedImage 在 draw() 里按
        // selectionRect 跟随，move 视觉一致；resize 控制点已被 drawAnnotationResizeHandles
        // 隐藏，因此到这里 selectionAdjust 必然是 .moving，不会出现 capturedImage 被拉伸的情况。

        // 工具栏不再 remove+rebuild，直接移到选区下方新位置避免淡入淡出闪烁。
        // 若 toolbar 不存在（异常路径）才走原 showAnnotationToolbar。
        if let panel = toolbarPanel {
            let target = toolbarTargetOrigin(width: panel.frame.width)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.16
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrameOrigin(target)
            }
        } else {
            showAnnotationToolbar()
        }
        needsDisplay = true
        // 释放后鼠标可能停在 move ring / resize 控制点上，下一次 mouseMoved 会自动按新
        // cursor rect 切换光标；这里只 invalidate 让 AppKit 重新评估即可，不主动 set。
        window?.invalidateCursorRects(for: self)
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
        // 成功路径：editPin 时旧钉图销毁（避免出现"老版本 + 新拖出去的钉图"两张）
        CaptureManager.shared.finishAndCloseDiscardingEditedPin()
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
            pushUndoSnapshot()
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

    /// ⌘S / 工具栏保存按钮：直接写到设置里的保存目录并关闭。
    ///
    /// 之前用 NSSavePanel.runModal 弹「另存为」对话框，但 OverlayWindow 是
    /// .screenSaver 层级（覆盖一切），普通 panel 层级低会被遮挡——用户感受
    /// 到的「点了没反应 / 好像有个确认对话」就是这个。NSAlert 在 promptText
    /// 那边踩过同样的坑。
    ///
    /// 想改保存路径请去「设置 > 保存目录」改，截图过程不再弹路径选择。
    private func performSave() {
        guard mode == .annotating else { return }
        silentSaveAndClose()
    }

    private func copyAndClose() {
        let image = renderFinalImage()
        copyImageToClipboard(image)
        CopyToast.show(image: image)
        // 成功路径：editPin 时旧钉图销毁，避免桌面遗留老版本
        CaptureManager.shared.finishAndCloseDiscardingEditedPin()
    }

    /// 按设置目录+格式直接写文件，不弹任何对话框
    ///
    /// 关键：ImageIO 编码（尤其 4K Retina PNG）+ 磁盘写入会耗 200~1000ms，
    /// 如果都在主线程上做，overlay 会"挂着不动"直到写完，用户感受为「卡住」。
    /// 这里把渲染（必须主线程，要读标注状态）留在前面，然后立刻关闭 overlay
    /// 并弹 toast；编码 + 写盘异步丢到后台队列，失败再回主线程补一个错误 toast。
    private func silentSaveAndClose() {
        let image = renderFinalImage()
        let format = UserDefaults.standard.string(forKey: UDKey.imageFormat) ?? "png"
        let url = OutputFileHelper.screenshotURL(format: format)
        let dir = url.deletingLastPathComponent()
        let filename = url.lastPathComponent
        let jpegQuality = UserDefaults.standard.object(forKey: UDKey.jpegQuality) as? Double ?? 0.85

        // 立即反馈：toast 先弹 + overlay 立刻关。后续的写盘失败再补一条错误 toast。
        CopyToast.show(image: image,
                       message: "已保存",
                       subtitle: filename)
        // 成功路径：editPin 时旧钉图销毁
        CaptureManager.shared.finishAndCloseDiscardingEditedPin()

        // primaryCGImage / encodeWithImageIO 只做 CG/ImageIO 计算，线程安全，
        // 这里直接派发到后台。失败回主线程兜底为复制 + 错误 toast。
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let cg = SelectionView.primaryCGImage(of: image) else {
                DispatchQueue.main.async {
                    self?.copyImageToClipboard(image)
                    CopyToast.show(image: image,
                                   message: "保存失败，已复制到剪贴板",
                                   subtitle: "无法获取图像像素数据")
                }
                return
            }
            let data: Data
            if format == "jpeg" {
                data = SelectionView.encodeWithImageIO(cgImage: cg, type: .jpeg, quality: jpegQuality)
            } else {
                data = SelectionView.encodeWithImageIO(cgImage: cg, type: .png, quality: nil)
            }
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try data.write(to: url)
            } catch {
                NSLog("[Snap2] 保存失败: \(error)")
                DispatchQueue.main.async {
                    self?.copyImageToClipboard(image)
                    CopyToast.show(image: image,
                                   message: "保存失败，已复制到剪贴板",
                                   subtitle: error.localizedDescription)
                }
            }
        }
    }

    /// 取出 NSImage 中第一张可用的 CGImage。
    /// 优先走 NSBitmapImageRep.cgImage（renderFinalImage 输出走的就是这条路径，
    /// 能完整保留 Display P3 等色彩空间），否则兜底用 NSImage.cgImage(forProposedRect:...)。
    ///
    /// 设为 static：silentSaveAndClose 的后台编码路径需要在非主线程上调用，
    /// 实例方法在 view 已 orderOut 后再被远程调起容易引起隐式 retain。
    static func primaryCGImage(of image: NSImage) -> CGImage? {
        if let bitmap = image.representations.first as? NSBitmapImageRep,
           let cg = bitmap.cgImage {
            return cg
        }
        var proposed = NSRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &proposed, context: nil, hints: nil)
    }

    /// 用 ImageIO 走 CGImageDestination 编码。
    /// 相比 NSBitmapImageRep.representation(using:)，这条路径会把 cgImage.colorSpace 完整写成 ICC profile，
    /// 修复 PNG 在 Chrome / 微信 / PS 等非系统 app 里被按 sRGB 解释而偏暗的问题。
    ///
    /// 设为 static：见 primaryCGImage 同名说明，需要从后台队列安全调用。
    static func encodeWithImageIO(cgImage: CGImage, type: UTType, quality: Double?) -> Data {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            return Data()
        }
        var properties: [CFString: Any] = [:]
        if type == .jpeg, let q = quality {
            properties[kCGImageDestinationLossyCompressionQuality] = max(0.0, min(1.0, q))
        }
        CGImageDestinationAddImage(dest, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return Data() }
        return data as Data
    }

    private func copyImageToClipboard(_ image: NSImage) {
        let pb = NSPasteboard.general
        pb.clearContents()

        // PNG 是关键路径：现代 app 几乎都从 pasteboard 读 PNG，所以必须走 ImageIO 把
        // Display P3 ICC profile 嵌入；否则 Chrome / 微信 / PS 会按 sRGB 解释 P3 像素。
        if let cg = SelectionView.primaryCGImage(of: image) {
            let pngData = SelectionView.encodeWithImageIO(cgImage: cg, type: .png, quality: nil)
            if !pngData.isEmpty {
                pb.setData(pngData, forType: .png)
            }
        }

        // TIFF：保留 image.tiffRepresentation 路径——NSBitmapImageRep 内部默认走 LZW
        // 压缩，剪贴板大小可控；且这是 macOS Cocoa 历史首选，PS / iWork 等老 app 优先读它。
        if let tiff = image.tiffRepresentation {
            pb.setData(tiff, forType: .tiff)
        }
    }

    private func renderFinalImage() -> NSImage {
        guard let bg = capturedImage else { return NSImage() }

        // 逻辑尺寸来自 NSImage.size（点），像素尺寸**优先**取直接持有的 CGImage（避免
        // NSImage.cgImage(forProposedRect:) 在某些机型/版本上把高分图重采样回点级分辨率
        // ——那是症状"分辨率特别低 + 抖动模糊"的根因）。
        let pointSize = bg.size
        guard pointSize.width > 0, pointSize.height > 0 else { return NSImage() }

        let bgCG: CGImage?
        if let direct = capturedCGImage {
            bgCG = direct
        } else {
            var proposed = NSRect(origin: .zero, size: pointSize)
            bgCG = bg.cgImage(forProposedRect: &proposed, context: nil, hints: nil)
        }

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

        // 用 Display P3 而非 deviceRGB：SCK 抓到的 CGImage 多为 P3，
        // 落到 deviceRGB 的位图会按 sRGB 解释 P3 像素，导致饱和色偏暗变灰。
        let colorSpace = bgCG?.colorSpace ?? CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo: UInt32 = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let cgContext = CGContext(
            data: nil,
            width: pixelW,
            height: pixelH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return NSImage() }

        // 切到像素坐标系：(0,0,pixelW,pixelH) 直接对应输出位图的像素网格，
        // 背景 CGImage 绘制走 1:1，无任何重采样。
        if let cg = bgCG {
            cgContext.interpolationQuality = .none
            cgContext.draw(cg, in: CGRect(x: 0, y: 0, width: pixelW, height: pixelH))
        } else {
            // 兜底：通过 NSGraphicsContext 让 NSImage 自己绘制，保留高质量插值
            let nsCtx = NSGraphicsContext(cgContext: cgContext, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = nsCtx
            bg.draw(in: NSRect(x: 0, y: 0, width: pixelW, height: pixelH),
                    from: .zero,
                    operation: .copy,
                    fraction: 1.0,
                    respectFlipped: false,
                    hints: [.interpolation: NSImageInterpolation.high])
            NSGraphicsContext.restoreGraphicsState()
        }

        // 标注是按"点"坐标记录的，绘制时需缩放到像素空间。
        // 用高质量插值 + 缩放变换，让箭头/线条在 Retina 上保持锐利不锯齿。
        let scaleX = CGFloat(pixelW) / pointSize.width
        let scaleY = CGFloat(pixelH) / pointSize.height
        cgContext.saveGState()
        cgContext.scaleBy(x: scaleX, y: scaleY)
        cgContext.interpolationQuality = .high
        cgContext.setShouldAntialias(true)
        cgContext.setAllowsAntialiasing(true)
        for el in elements {
            toolRegistry.tool(for: el.toolType)?.draw(element: el, in: cgContext)
        }
        cgContext.restoreGState()

        guard let outCG = cgContext.makeImage() else { return NSImage() }
        let outRep = NSBitmapImageRep(cgImage: outCG)
        outRep.size = pointSize
        let result = NSImage(size: pointSize)
        result.addRepresentation(outRep)
        return result
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
        // 数值是像素（× backingScale），加 px 后缀避免与"点"单位混淆。
        let text = " \(Int(selectionRect.width * scale)) × \(Int(selectionRect.height * scale)) px "
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
            // 标注模式：cursor rect 注册顺序 = 先具体后宽泛（与 .selecting 模式同语义，
            // AppKit 在多个重叠 rect 命中时取先注册者）。

            // 1. 钉图拖动手柄：最高优先级
            if let h = pinHandleRect() {
                addCursorRect(h, cursor: .openHand)
            }

            // 2. resize 控制点：用方向感更明确的 resize 光标盖到圆点 hit-pad 区域
            let resizeCursors: [NSCursor] = [
                .resizeUpDown, .resizeUpDown, .resizeUpDown, .resizeUpDown,  // 4 角统一用上下，AppKit 没有公开斜向光标
                .resizeUpDown, .resizeLeftRight, .resizeUpDown, .resizeLeftRight  // T R B L
            ]
            for (i, h) in annotationResizeHandleRects.enumerated() {
                addCursorRect(h.insetBy(dx: -annotationHandleHitPad, dy: -annotationHandleHitPad),
                              cursor: resizeCursors[i])
            }

            // 3. 外侧 move ring：openHand 提示可拖动整个选区
            if selectionRect.width > 0, selectionRect.height > 0 {
                let outer = selectionRect.insetBy(dx: -annotationMoveRingWidth, dy: -annotationMoveRingWidth)
                // ring 形区域用 4 条矩形拼出来（顶/底/左/右）
                let top = NSRect(x: outer.minX, y: selectionRect.maxY,
                                 width: outer.width, height: outer.maxY - selectionRect.maxY)
                let bottom = NSRect(x: outer.minX, y: outer.minY,
                                    width: outer.width, height: selectionRect.minY - outer.minY)
                let left = NSRect(x: outer.minX, y: selectionRect.minY,
                                  width: selectionRect.minX - outer.minX, height: selectionRect.height)
                let right = NSRect(x: selectionRect.maxX, y: selectionRect.minY,
                                   width: outer.maxX - selectionRect.maxX, height: selectionRect.height)
                for r in [top, bottom, left, right] where r.width > 0 && r.height > 0 {
                    addCursorRect(r, cursor: .openHand)
                }
            }

            // 4. 选区内部：绘制 crosshair（兜底）
            addCursorRect(selectionRect, cursor: .crosshair)
        }
    }
}

// MARK: - GlassToolbarDelegate

extension SelectionView: GlassToolbarDelegate {
    func toolbarDidPickTool(_ tool: AnnotationToolType) {
        currentTool = tool
        AnnotationPreferences.saveTool(tool)
    }
    func toolbarDidPickColor(_ color: NSColor) {
        currentColor = color
        AnnotationPreferences.saveColor(color)
    }
    func toolbarDidPickWidth(_ width: CGFloat) {
        currentLineWidth = width
        AnnotationPreferences.saveLineWidth(width)
    }
    func toolbarDidTapUndo() { performUndo() }
    func toolbarDidTapSave() { performSave() }
    func toolbarDidTapCopy() { copyAndClose() }
    func toolbarDidTapPin()  { performPinAtSelection() }
    func toolbarDidTapRecord() { performRecordSelection() }
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
        // 成功路径：editPin 时旧钉图销毁
        CaptureManager.shared.finishAndCloseDiscardingEditedPin()
    }

    /// 工具栏录制按钮：把当前选区交给 RecordingManager 直接录屏，
    /// 期间标注不会被保留（视频只录原始画面）。
    private func performRecordSelection() {
        guard mode == .annotating else { return }
        // 用 OverlayWindow.targetScreen 而不是 window?.screen——后者在 overlay 拆解期间可能瞬时返回 nil
        let screen: NSScreen? = (window as? OverlayWindow)?.targetScreen ?? window?.screen
        guard let screen = screen else { return }
        // 捕获 rect / screen 后再拆 overlay，避免拆窗后丢失关联
        let rect = selectionRect
        // 成功路径（用户主动转录屏）：editPin 时旧钉图销毁，避免录屏期间桌面又冒出来
        CaptureManager.shared.finishAndCloseDiscardingEditedPin()
        // 派发到下一轮 runloop：让 overlay orderOut 完成、SCStream 旧会话释放后再启动新流
        DispatchQueue.main.async {
            RecordingManager.shared.startRecordingForRegion(rect, on: screen)
        }
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
