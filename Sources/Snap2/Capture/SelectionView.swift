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

        // 1. 全屏遮罩（深色）
        context.saveGState()
        DrawingDefaults.overlayColor.setFill()
        context.fill(bounds)
        context.restoreGState()

        guard selectionRect.width > 0, selectionRect.height > 0 else { return }

        // 2. 选区清透
        context.saveGState()
        context.setBlendMode(.clear)
        context.fill(selectionRect)
        context.restoreGState()

        switch mode {
        case .selecting:
            drawSelectionChrome(in: context)
        case .annotating:
            if let image = capturedImage {
                image.draw(in: selectionRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            }
            drawAnnotations(in: context)
            drawAnnotationFrame(in: context)
        }
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

    override func mouseUp(with event: NSEvent) {
        if mode == .annotating {
            handleAnnotationMouseUp(p: convert(event.locationInWindow, from: nil))
            return
        }

        let wasCreating = (selectionRect.width > 2 && selectionRect.height > 2)
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
        let screenFrame = screen.frame
        let captureRect = NSRect(
            x: screenFrame.origin.x + selectionRect.origin.x,
            y: screenFrame.origin.y + selectionRect.origin.y,
            width: selectionRect.width,
            height: selectionRect.height
        )

        hideSizeBadge()

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

    // MARK: - 标注鼠标

    private func handleAnnotationMouseDown(p: NSPoint, event: NSEvent) {
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
        guard let el = currentElement else { return }
        let local = NSPoint(x: p.x - selectionRect.origin.x,
                            y: p.y - selectionRect.origin.y)
        if el.toolType == .freedraw { el.points.append(local) }
        else { el.endPoint = local }
        needsDisplay = true
    }

    private func handleAnnotationMouseUp(p: NSPoint) {
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

    private func isValid(_ el: AnnotationElement) -> Bool {
        switch el.toolType {
        case .freedraw: return el.points.count >= 2
        case .text: return el.text != nil && !(el.text?.isEmpty ?? true)
        default:
            return abs(el.endPoint.x - el.startPoint.x) > 2 || abs(el.endPoint.y - el.startPoint.y) > 2
        }
    }

    private func promptText(at point: NSPoint) {
        let alert = NSAlert()
        alert.messageText = "输入标注文字"
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")
        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        tf.placeholderString = "在此输入..."
        alert.accessoryView = tf
        if alert.runModal() == .alertFirstButtonReturn, !tf.stringValue.isEmpty {
            let el = AnnotationElement(toolType: .text, color: currentColor, lineWidth: currentLineWidth)
            el.startPoint = point
            el.endPoint = point
            el.text = tf.stringValue
            el.font = NSFont.systemFont(ofSize: max(currentLineWidth * 6, 14))
            undoStack.append(elements)
            elements.append(el)
            needsDisplay = true
        }
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
        if let tiff = image.tiffRepresentation {
            pb.setData(tiff, forType: .tiff)
            if let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                pb.setData(png, forType: .png)
            }
        }
    }

    /// 按设置编码：返回 (数据, 扩展名)
    private func encode(_ image: NSImage) -> (Data, String) {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff)
        else { return (Data(), "png") }

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
        let size = bg.size
        let img = NSImage(size: size)
        img.lockFocus()
        bg.draw(in: NSRect(origin: .zero, size: size))
        if let ctx = NSGraphicsContext.current?.cgContext {
            for el in elements {
                toolRegistry.tool(for: el.toolType)?.draw(element: el, in: ctx)
            }
        }
        img.unlockFocus()
        return img
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
        toolbar.frame = NSRect(x: 0, y: 0, width: width, height: height)
        toolbar.autoresizingMask = [.width, .height]
        panel.contentBox.addSubview(toolbar)

        positionToolbar(panel)

        if let parent = window {
            parent.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)
        toolbarPanel = panel
        toolbarView = toolbar
    }

    private func positionToolbar(_ panel: GlassPanel) {
        guard let screen = window?.screen ?? NSScreen.main else { return }
        // 贴屏幕底部居中（visibleFrame 已避开 dock）
        let visible = screen.visibleFrame
        let bottomGap: CGFloat = 8
        let x = visible.minX + (visible.width - panel.frame.width) / 2
        let y = visible.minY + bottomGap
        panel.setFrameOrigin(NSPoint(x: x, y: y))
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

        // 位置：选区上方居中；放不下放下面
        let so = pw.frame.origin
        var x = so.x + selectionRect.midX - w / 2
        var y = so.y + selectionRect.maxY + 8
        let screenFrame = pw.screen?.frame ?? pw.frame
        if y + 28 > so.y + screenFrame.height - 8 {
            y = so.y + selectionRect.minY - 28 - 8
        }
        x = max(so.x + 8, min(x, so.x + screenFrame.width - w - 8))
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
    func toolbarDidTapClose() { CaptureManager.shared.cancelCapture() }
}
