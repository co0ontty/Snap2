import AppKit
import Carbon.HIToolbox

// MARK: - 全局快捷键管理器
/// 使用 Carbon API 注册系统级全局热键，支持在任何应用中触发截图
class HotkeyManager {

    // MARK: - 单例
    static let shared = HotkeyManager()

    // MARK: - 默认快捷键：Ctrl+Shift+A
    private static let defaultKeyCode: UInt32   = UInt32(kVK_ANSI_A)
    private static let defaultModifiers: UInt32 = UInt32(controlKey | shiftKey)  // Carbon 修饰键

    // MARK: - 私有属性
    private var hotkeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    /// 当前已注册的 keyCode（Carbon 虚拟键码）
    private(set) var currentKeyCode: UInt32 = 0
    /// 当前已注册的修饰键（Carbon 修饰键掩码）
    private(set) var currentModifiers: UInt32 = 0

    // MARK: - 热键 ID（用于区分多个热键，这里只用一个）
    private let hotkeyID = EventHotKeyID(signature: OSType(0x534E5032), // "SNP2" 的 ASCII
                                          id: 1)

    // MARK: - 初始化
    private init() {
        loadFromDefaults()
        installEventHandler()
        registerHotkey()
    }

    deinit {
        unregisterHotkey()
        if let handler = eventHandler {
            RemoveEventHandler(handler)
        }
    }

    // MARK: - 从 UserDefaults 读取配置
    private func loadFromDefaults() {
        let defaults = UserDefaults.standard

        if defaults.object(forKey: UDKey.hotkeyKeyCode) != nil {
            currentKeyCode   = UInt32(defaults.integer(forKey: UDKey.hotkeyKeyCode))
            currentModifiers = UInt32(defaults.integer(forKey: UDKey.hotkeyModifiers))
        } else {
            // 首次运行，使用默认值
            currentKeyCode   = Self.defaultKeyCode
            currentModifiers = Self.defaultModifiers
        }
    }

    // MARK: - 保存配置到 UserDefaults
    private func saveToDefaults() {
        let defaults = UserDefaults.standard
        defaults.set(Int(currentKeyCode), forKey: UDKey.hotkeyKeyCode)
        defaults.set(Int(currentModifiers), forKey: UDKey.hotkeyModifiers)
    }

    // MARK: - 安装 Carbon 事件处理器
    private func installEventHandler() {
        // 定义感兴趣的事件类型：热键按下
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // 安装全局事件处理器
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            hotkeyEventCallback,
            1,
            &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandler
        )

        if status != noErr {
            NSLog("[HotkeyManager] 安装事件处理器失败，错误码: \(status)")
        }
    }

    // MARK: - 注册全局热键
    func registerHotkey() {
        // 先注销已有热键
        unregisterHotkey()

        let hotKeyID = hotkeyID
        let status = RegisterEventHotKey(
            currentKeyCode,
            currentModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )

        if status != noErr {
            NSLog("[HotkeyManager] 注册热键失败，错误码: \(status)")
        }
    }

    // MARK: - 注销全局热键
    func unregisterHotkey() {
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
            hotkeyRef = nil
        }
    }

    // MARK: - 公开方法：更新快捷键
    /// 供设置界面调用，更新全局快捷键
    /// - Parameters:
    ///   - keyCode: Carbon 虚拟键码 (kVK_*)
    ///   - modifiers: Carbon 修饰键掩码 (cmdKey, shiftKey, optionKey, controlKey)
    func updateHotkey(keyCode: UInt32, modifiers: UInt32) {
        currentKeyCode   = keyCode
        currentModifiers = modifiers
        saveToDefaults()
        registerHotkey()
        NotificationCenter.default.post(name: .hotkeyChanged, object: nil)
    }

    // MARK: - 公开方法：恢复默认快捷键
    func resetToDefault() {
        updateHotkey(keyCode: Self.defaultKeyCode, modifiers: Self.defaultModifiers)
    }

    // MARK: - 将 NSEvent 修饰键转换为 Carbon 修饰键
    static func carbonModifiers(from cocoaModifiers: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if cocoaModifiers.contains(.command) {
            carbon |= UInt32(cmdKey)
        }
        if cocoaModifiers.contains(.shift) {
            carbon |= UInt32(shiftKey)
        }
        if cocoaModifiers.contains(.option) {
            carbon |= UInt32(optionKey)
        }
        if cocoaModifiers.contains(.control) {
            carbon |= UInt32(controlKey)
        }
        return carbon
    }

    // MARK: - 将 Carbon 修饰键转换为 NSEvent 修饰键
    static func cocoaModifiers(from carbonMods: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbonMods & UInt32(cmdKey) != 0 {
            flags.insert(.command)
        }
        if carbonMods & UInt32(shiftKey) != 0 {
            flags.insert(.shift)
        }
        if carbonMods & UInt32(optionKey) != 0 {
            flags.insert(.option)
        }
        if carbonMods & UInt32(controlKey) != 0 {
            flags.insert(.control)
        }
        return flags
    }

    // MARK: - 热键触发处理
    fileprivate func handleHotkeyEvent() {
        // 在主线程发送通知
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .captureRequested, object: nil)
        }
    }
}

// MARK: - Carbon 事件回调（C 函数指针）
/// Carbon API 要求使用 C 风格回调函数
private func hotkeyEventCallback(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData = userData else { return OSStatus(eventNotHandledErr) }

    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
    manager.handleHotkeyEvent()
    return noErr
}
