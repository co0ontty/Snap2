import AppKit

/// 全屏透明覆盖窗口
/// 每个屏幕上创建一个，用于捕获用户的鼠标选区操作
class OverlayWindow: NSWindow {

    // MARK: - 初始化

    /// 在指定屏幕上创建全屏覆盖窗口
    /// - Parameter screen: 要覆盖的屏幕
    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        setupWindow()
    }

    // MARK: - 配置

    private func setupWindow() {
        // 窗口层级设置为 screenSaver，确保覆盖在所有窗口之上
        level = .screenSaver

        // 透明窗口配置
        isOpaque = false
        hasShadow = false
        backgroundColor = .clear

        // 接收鼠标事件
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true

        // 可以在所有 Space 中显示
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // 设置选区视图作为内容视图和 firstResponder
        let selectionView = SelectionView(frame: contentRect(forFrameRect: frame))
        contentView = selectionView
        _ = makeFirstResponder(selectionView)
    }

    // MARK: - 键盘事件

    /// 允许窗口成为 key window 以接收键盘事件
    override var canBecomeKey: Bool {
        return true
    }

    /// 允许窗口成为 main window
    override var canBecomeMain: Bool {
        return true
    }

    /// 让 firstResponder（SelectionView）自然接收键盘事件
    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        // 确保 SelectionView 总是 firstResponder
        if responder == nil || responder === self {
            return super.makeFirstResponder(contentView)
        }
        return super.makeFirstResponder(responder)
    }
}
