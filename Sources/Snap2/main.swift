// Snap² - macOS 截图工具
// 入口文件：创建 NSApplication，设置 AppDelegate，启动运行循环

import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
