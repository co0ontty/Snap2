import AppKit

protocol RecordingSelectionViewDelegate: AnyObject {
    /// 用户点 "开始录屏" / 回车确认。selectionRect 是视图坐标系；screen 是该 overlay 所在屏。
    func recordingSelectionDidConfirm(_ view: RecordingSelectionView,
                                      selectionInView rect: NSRect,
                                      screen: NSScreen)
    /// 用户点 "取消" / Esc。
    func recordingSelectionDidCancel(_ view: RecordingSelectionView)
}

/// 录屏取景视图。
///
/// 复用截图 `.selecting` 模式的视觉语言（暗色蒙版 + 选区清空 + 8 个 resize 控制点 + 12px move ring），
/// 但**没有** annotation 状态，**不**走标注模式——选区松手后弹一个"▶ 开始录屏 / ✕ 取消"
/// 玻璃确认条，由用户主动确认才会真正启动录制。
///
/// 不抓 frozenImage：录屏取景期间桌面是活的（用户可能要瞄准动态目标），用 blend = clear
/// 路径让选区内透出实时桌面。
final class RecordingSelectionView: NSView {

    weak var delegate: RecordingSelectionViewDelegate?
    /// 该 overlay 所在屏幕。RecordingManager 在创建时塞过来，用于 confirm 时回传。
    weak var targetScreen: NSScreen?

    // MARK: - 选区状态

    private var selectionRect: NSRect = .zero
    private var dragOrigin: NSPoint?
    private var isAdjusting: Bool = false

    private enum DragKind { case create, move, resize(Int) }
    private var dragKind: DragKind = .create
    private var moveOffset: NSPoint = .zero
    private var resizeAnchor: NSPoint = .zero

    private let moveRingWidth: CGFloat = 12

    private var confirmPanel: GlassPanel?
    private let sizeBadge = SizeBadge()

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

        let hasSelection = selectionRect.width > 0 && selectionRect.height > 0

        // 暗色蒙版：选区内用 blend = clear 抠出去，让活桌面透出
        context.saveGState()
        DrawingDefaults.overlayColor.setFill()
        if hasSelection {
            context.fill(bounds)
            context.setBlendMode(.clear)
            context.fill(selectionRect)
        } else {
            context.fill(bounds)
        }
        context.restoreGState()

        guard hasSelection else { return }

        // 选区边框（1px 内白，与截图风格一致）+ 强调色发光
        context.saveGState()
        NSColor.systemRed.withAlphaComponent(0.85).setStroke()
        context.setLineWidth(1.5)
        context.stroke(selectionRect)
        context.restoreGState()

        drawHandles(in: context)
        drawRecBadge(in: context)
    }

    /// 在选区左上角外侧绘制「● REC」红色徽章，与截图模式做明显视觉区分。
    /// 用户系统强调色就是红色时，仅靠边框颜色不足以让人意识到当前在录屏。
    private func drawRecBadge(in context: CGContext) {
        // 选区太小时不绘制（避免遮挡）
        guard selectionRect.width > 80, selectionRect.height > 40 else { return }

        let badgeHeight: CGFloat = 22
        let badgePadX: CGFloat = 10
        let dotSize: CGFloat = 8
        let labelText = "REC"

        let font = NSFont.systemFont(ofSize: 11, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
        ]
        let textSize = (labelText as NSString).size(withAttributes: attrs)
        let badgeWidth = badgePadX + dotSize + 6 + textSize.width + badgePadX

        // 贴选区左上外侧 6px
        let bx = selectionRect.minX
        let by = selectionRect.maxY + 6
        let badgeRect = NSRect(x: bx, y: by, width: badgeWidth, height: badgeHeight)

        context.saveGState()
        // 圆角红底
        let path = CGPath(roundedRect: badgeRect,
                          cornerWidth: Glass.radiusBadge,
                          cornerHeight: Glass.radiusBadge,
                          transform: nil)
        context.addPath(path)
        NSColor.systemRed.withAlphaComponent(0.92).setFill()
        context.fillPath()
        // 1px 白色描边
        context.addPath(path)
        NSColor.white.withAlphaComponent(0.4).setStroke()
        context.setLineWidth(1)
        context.strokePath()

        // 白点
        let dotRect = NSRect(x: bx + badgePadX,
                             y: by + (badgeHeight - dotSize) / 2,
                             width: dotSize, height: dotSize)
        context.addPath(CGPath(ellipseIn: dotRect, transform: nil))
        NSColor.white.setFill()
        context.fillPath()
        context.restoreGState()

        // 文字 REC（绘制时切到 NSGraphicsContext）
        NSGraphicsContext.saveGraphicsState()
        let nsCtx = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current = nsCtx
        let textPoint = NSPoint(
            x: bx + badgePadX + dotSize + 6,
            y: by + (badgeHeight - textSize.height) / 2
        )
        (labelText as NSString).draw(at: textPoint, withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawHandles(in context: CGContext) {
        SelectionHandles.drawSelecting(in: context, rects: handleRects)
    }

    // MARK: - Handles

    private var handleRects: [NSRect] {
        SelectionHandles.rects(for: selectionRect)
    }

    private func anchorForHandle(_ i: Int) -> NSPoint {
        SelectionHandles.anchor(i, of: selectionRect)
    }

    // MARK: - 鼠标事件

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)

        // 命中手柄 → resize
        if let i = SelectionHandles.hitIndex(at: p, in: selectionRect) {
            dragKind = .resize(i)
            resizeAnchor = anchorForHandle(i)
            isAdjusting = true
            hideConfirmToolbar()  // 调整时先把确认条收掉，松手再回来
            showSizeBadge()
            updateSizeBadge()
            return
        }
        // 选区内 → move
        if selectionRect.width > 0, selectionRect.height > 0, selectionRect.contains(p) {
            dragKind = .move
            moveOffset = NSPoint(x: p.x - selectionRect.origin.x, y: p.y - selectionRect.origin.y)
            isAdjusting = true
            NSCursor.closedHand.set()
            hideConfirmToolbar()
            showSizeBadge()
            updateSizeBadge()
            return
        }
        // 选区外的 12px ring → move（更宽裕的命中区）
        if hasSelection, hitMoveRing(p) {
            dragKind = .move
            moveOffset = NSPoint(x: p.x - selectionRect.origin.x, y: p.y - selectionRect.origin.y)
            isAdjusting = true
            NSCursor.closedHand.set()
            hideConfirmToolbar()
            showSizeBadge()
            updateSizeBadge()
            return
        }
        // 否则：新建选区
        dragKind = .create
        dragOrigin = p
        selectionRect = .zero
        isAdjusting = true
        hideConfirmToolbar()
        showSizeBadge()
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
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
        isAdjusting = false
        dragOrigin = nil
        NSCursor.crosshair.set()

        // 选区有效（≥10×10）→ 弹确认条；过小重置
        if selectionRect.width > 10, selectionRect.height > 10 {
            hideSizeBadge()
            showConfirmToolbar()
        } else {
            selectionRect = .zero
            hideSizeBadge()
        }
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    private func applyResize(handleIndex i: Int, point p: NSPoint) {
        selectionRect = SelectionHandles.resizedSelection(handle: i, to: p,
                                                          from: selectionRect, anchor: resizeAnchor)
    }

    private var hasSelection: Bool {
        selectionRect.width > 0 && selectionRect.height > 0
    }

    private func hitMoveRing(_ p: NSPoint) -> Bool {
        guard hasSelection else { return false }
        if selectionRect.contains(p) { return false }
        let outer = selectionRect.insetBy(dx: -moveRingWidth, dy: -moveRingWidth)
        return outer.contains(p)
    }

    // MARK: - 键盘

    override func keyDown(with event: NSEvent) {
        // Esc 取消
        if event.keyCode == 53 {
            delegate?.recordingSelectionDidCancel(self)
            return
        }
        // Enter 确认（仅在选区已成型时）
        if event.keyCode == 36 || event.keyCode == 76, hasSelection {
            confirmStart()
            return
        }
        super.keyDown(with: event)
    }

    private func confirmStart() {
        guard let screen = targetScreen else {
            delegate?.recordingSelectionDidCancel(self)
            return
        }
        hideConfirmToolbar()
        hideSizeBadge()
        delegate?.recordingSelectionDidConfirm(self, selectionInView: selectionRect, screen: screen)
    }

    // MARK: - 确认条（开始 / 取消）

    private func showConfirmToolbar() {
        if confirmPanel != nil { return }
        let height: CGFloat = 38
        let width: CGFloat = 158  // 适配两个按钮 + 间距

        let panel = GlassPanel(size: NSSize(width: width, height: height),
                               cornerRadius: Glass.radiusCard)
        let host = panel.contentBox

        let startBtn = GlassButton(symbol: "record.circle",
                                    size: 28,
                                    tooltip: "开始录屏 (Enter)")
        startBtn.accentColor = .systemRed
        startBtn.target = self
        startBtn.action = #selector(startTapped)

        let startLabel = NSTextField(labelWithString: "开始")
        startLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        startLabel.textColor = .white
        startLabel.backgroundColor = .clear
        startLabel.isBezeled = false
        startLabel.isEditable = false

        let cancelBtn = GlassButton(symbol: "xmark",
                                    size: 28,
                                    tooltip: "取消 (Esc)")
        cancelBtn.target = self
        cancelBtn.action = #selector(cancelTapped)

        let stack = NSStackView(views: [startBtn, startLabel, cancelBtn])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: host.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: host.trailingAnchor),
        ])

        let target = confirmToolbarTargetOrigin(width: width)
        // 先入场（alpha 0 起步）再挂子窗口，避免在旧 frame 处闪一帧
        PanelFX.animateIn(panel: panel, to: target)
        if let parent = window {
            parent.addChildWindow(panel, ordered: .above)
        }
        confirmPanel = panel
    }

    private func hideConfirmToolbar() {
        if let p = confirmPanel {
            p.parent?.removeChildWindow(p)
            p.orderOut(nil)
        }
        confirmPanel = nil
    }

    private func confirmToolbarTargetOrigin(width: CGFloat) -> NSPoint {
        guard let pw = window, let screen = pw.screen ?? NSScreen.main else { return .zero }
        let visible = screen.visibleFrame
        let height: CGFloat = 38
        let gap: CGFloat = 8
        let edgeMargin: CGFloat = 8

        let so = pw.frame.origin
        let selBottomY = so.y + selectionRect.minY
        let selCenterX = so.x + selectionRect.midX

        var x = selCenterX - width / 2
        let minX = visible.minX + edgeMargin
        let maxX = visible.maxX - width - edgeMargin
        if maxX >= minX {
            x = max(minX, min(x, maxX))
        }

        var y = selBottomY - gap - height
        if y < visible.minY + edgeMargin {
            y = selBottomY + gap
            let maxOriginY = visible.maxY - height - edgeMargin
            y = max(visible.minY + edgeMargin, min(y, maxOriginY))
        }
        return NSPoint(x: x, y: y)
    }

    @objc private func startTapped() {
        DispatchQueue.main.async { [weak self] in
            self?.confirmStart()
        }
    }

    @objc private func cancelTapped() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.recordingSelectionDidCancel(self)
        }
    }

    // MARK: - 尺寸徽章（复用截图样式）

    private func showSizeBadge() {
        sizeBadge.show(attachedTo: window)
    }

    private func updateSizeBadge() {
        guard selectionRect.width > 0, selectionRect.height > 0, let pw = window else { return }
        let scale = pw.screen?.backingScaleFactor ?? 1.0
        let text = " \(Int(selectionRect.width * scale)) × \(Int(selectionRect.height * scale)) "
        sizeBadge.update(text: text, relativeTo: selectionRect, in: pw)
    }

    private func hideSizeBadge() {
        sizeBadge.hide()
    }

    // MARK: - 关闭清理（RecordingManager 在关 overlay 前调用）

    func prepareForClose() {
        hideConfirmToolbar()
        hideSizeBadge()
    }

    // MARK: - 光标

    override func resetCursorRects() {
        discardCursorRects()
        if hasSelection {
            // 1. resize handles 优先
            for (i, h) in handleRects.enumerated() {
                addCursorRect(h.insetBy(dx: -SelectionHandles.hitPad, dy: -SelectionHandles.hitPad),
                              cursor: SelectionHandles.cursor(forHandle: i))
            }
            // 2. 选区内：openHand 提示可拖
            addCursorRect(selectionRect, cursor: .openHand)
            // 3. 外侧 move ring
            let outer = selectionRect.insetBy(dx: -moveRingWidth, dy: -moveRingWidth)
            let top = NSRect(x: outer.minX, y: selectionRect.maxY,
                             width: outer.width, height: outer.maxY - selectionRect.maxY)
            let bot = NSRect(x: outer.minX, y: outer.minY,
                             width: outer.width, height: selectionRect.minY - outer.minY)
            let lf = NSRect(x: outer.minX, y: selectionRect.minY,
                            width: selectionRect.minX - outer.minX, height: selectionRect.height)
            let rt = NSRect(x: selectionRect.maxX, y: selectionRect.minY,
                            width: outer.maxX - selectionRect.maxX, height: selectionRect.height)
            for r in [top, bot, lf, rt] where r.width > 0 && r.height > 0 {
                addCursorRect(r, cursor: .openHand)
            }
        }
        addCursorRect(bounds, cursor: .crosshair)
    }
}
