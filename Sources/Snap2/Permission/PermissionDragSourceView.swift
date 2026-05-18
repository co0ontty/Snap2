import AppKit
import Foundation

/// 气泡内"图标 + 应用名"的可拖拽行。
///
/// 把这一行拖到「系统设置 → 隐私与安全性 → 屏幕录制 / 辅助功能」的列表里，等同于
/// 用户从 Finder 拖了 .app 进去——剪贴板写入的是 `.fileURL = Bundle URL`，macOS
/// 系统设置接受这种 fileURL，会自动把应用加入列表并开启开关。
///
/// 视觉上跟项目其他玻璃 UI 一致：暗色低对比的卡片背景 + 描边，避免抢气泡主体的注意力。
final class PermissionDragSourceView: NSView, NSPasteboardItemDataProvider, NSDraggingSource {
    private let hostApp: PermissionHostApp
    private let rowView = NSView()
    private let iconChrome = NSView()
    private let label = NSTextField(labelWithString: "")

    init(hostApp: PermissionHostApp) {
        self.hostApp = hostApp
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - 鼠标 → 拖拽会话

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let item = NSPasteboardItem()
        item.setDataProvider(self, forTypes: [.fileURL])

        let drag = NSDraggingItem(pasteboardWriter: item)
        drag.setDraggingFrame(convert(rowView.bounds, from: rowView),
                              contents: snapshotImage())

        let session = beginDraggingSession(with: [drag], event: event, source: self)
        // 用户在禁用区域松手 / 取消时，让拖拽影子飞回原位，避免"突兀消失"。
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    // MARK: - NSPasteboardItemDataProvider

    func pasteboard(_ pasteboard: NSPasteboard?,
                    item: NSPasteboardItem,
                    provideDataForType type: NSPasteboard.PasteboardType)
    {
        guard type == .fileURL else { return }
        item.setData(hostApp.bundleURL.dataRepresentation, forType: .fileURL)
    }

    // MARK: - NSDraggingSource

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext)
        -> NSDragOperation { .copy }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        // 拖拽过程中保留行轮廓、只降透明度作为"已被拖走"占位，气泡仍是完整形状。
        rowView.animator().alphaValue = 0.35
    }

    func draggingSession(_ session: NSDraggingSession,
                         endedAt screenPoint: NSPoint,
                         operation: NSDragOperation)
    {
        rowView.animator().alphaValue = 1.0
    }

    // MARK: - UI

    private func setup() {
        wantsLayer = true

        rowView.wantsLayer = true
        rowView.layer?.cornerRadius = 7
        rowView.layer?.borderWidth = 1
        rowView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
        rowView.layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        rowView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rowView)

        // 图标的小白底，避免 .icns 自身透明背景在暗色玻璃上看起来"陷下去"
        iconChrome.wantsLayer = true
        iconChrome.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.92).cgColor
        iconChrome.layer?.cornerRadius = 6
        iconChrome.translatesAutoresizingMaskIntoConstraints = false
        rowView.addSubview(iconChrome)

        let iconView = NSImageView(image: hostApp.icon)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconChrome.addSubview(iconView)

        label.stringValue = hostApp.displayName
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = NSColor.white.withAlphaComponent(0.92)
        label.translatesAutoresizingMaskIntoConstraints = false
        rowView.addSubview(label)

        NSLayoutConstraint.activate([
            rowView.leadingAnchor.constraint(equalTo: leadingAnchor),
            rowView.trailingAnchor.constraint(equalTo: trailingAnchor),
            rowView.topAnchor.constraint(equalTo: topAnchor),
            rowView.bottomAnchor.constraint(equalTo: bottomAnchor),

            iconChrome.leadingAnchor.constraint(equalTo: rowView.leadingAnchor, constant: 10),
            iconChrome.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),
            iconChrome.widthAnchor.constraint(equalToConstant: 28),
            iconChrome.heightAnchor.constraint(equalToConstant: 28),

            iconView.centerXAnchor.constraint(equalTo: iconChrome.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconChrome.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22),

            label.leadingAnchor.constraint(equalTo: iconChrome.trailingAnchor, constant: 11),
            label.trailingAnchor.constraint(lessThanOrEqualTo: rowView.trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),
        ])
    }

    /// 拖拽时跟手的飞影——直接把行渲染成图片。
    private func snapshotImage() -> NSImage {
        let image = NSImage(size: rowView.bounds.size)
        image.lockFocus()
        if let ctx = NSGraphicsContext.current {
            rowView.displayIgnoringOpacity(rowView.bounds, in: ctx)
        }
        image.unlockFocus()
        return image
    }
}
