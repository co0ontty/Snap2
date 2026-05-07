import AppKit

/// 自动更新过程的进度窗口：下载 → 解压 → 等待用户确认重启。
final class UpdateProgressWindow: NSWindowController {

    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let progress = NSProgressIndicator()
    private let cancelButton = NSButton(title: "取消", target: nil, action: nil)

    var onCancel: (() -> Void)?

    init() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 140),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        win.title = "Snap² 更新"
        win.isReleasedWhenClosed = false
        win.level = .floating
        super.init(window: win)

        buildLayout()
        cancelButton.target = self
        cancelButton.action = #selector(cancelTapped)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildLayout() {
        guard let content = window?.contentView else { return }
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 18, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
        ])

        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        detailLabel.font = NSFont.systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor

        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 1
        progress.style = .bar
        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.widthAnchor.constraint(equalToConstant: 340).isActive = true

        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(progress)
        stack.addArrangedSubview(detailLabel)

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.distribution = .fill
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        buttonRow.addArrangedSubview(spacer)
        buttonRow.addArrangedSubview(cancelButton)
        stack.addArrangedSubview(buttonRow)
    }

    func showCentered() {
        guard let win = window else { return }
        win.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func setDownloading(received: Int64, total: Int64) {
        titleLabel.stringValue = "正在下载新版本..."
        if total > 0 {
            let ratio = max(0, min(1, Double(received) / Double(total)))
            progress.isIndeterminate = false
            progress.doubleValue = ratio
            detailLabel.stringValue = "\(formatBytes(received)) / \(formatBytes(total)) (\(Int(ratio * 100))%)"
        } else {
            progress.isIndeterminate = true
            progress.startAnimation(nil)
            detailLabel.stringValue = "已下载 \(formatBytes(received))"
        }
    }

    func setExtracting() {
        titleLabel.stringValue = "解压中..."
        detailLabel.stringValue = "正在准备新版本"
        progress.isIndeterminate = true
        progress.startAnimation(nil)
    }

    @objc private func cancelTapped() {
        onCancel?()
        close()
    }

    private func formatBytes(_ n: Int64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useMB, .useKB]
        f.countStyle = .file
        return f.string(fromByteCount: n)
    }
}
